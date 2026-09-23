"""Dataset validation, deterministic snapshot date, and provenance."""
import csv
import hashlib
import json
from collections import defaultdict
from datetime import date
from pathlib import Path

from .models import Activity, Employee, Event, Role, Skill


class Dataset:
    def __init__(self, raw: dict):
        self.raw = raw
        self.as_of = date.fromisoformat(raw['as_of_date'])
        self.employees = self._index(Employee, raw['employees'], 'employee_id')
        self.events = self._index(Event, raw['events'], 'event_id')
        self.skills = self._index(Skill, raw['skills'], 'skill_id')
        self.roles = {}
        for item in raw['role_profiles']:
            r = Role.model_validate(item)
            key = (r.role, r.grade)
            if key in self.roles:
                raise ValueError(f'Duplicate role profile {key}')
            self.roles[key] = r
        self.activities = list(self._index(Activity, raw['activity_history'], 'record_id').values())
        self.by_employee = defaultdict(list)
        self.warnings = []
        self._validate()
        for row in sorted(self.activities, key=lambda r: (r.date, r.record_id)):
            self.by_employee[row.employee_id].append(row)
        # Normalise CSV strings and JSON numbers before comparing imports or revisions.
        self.raw = dict(as_of_date=self.as_of.isoformat(),
                        employees=[e.model_dump(mode='json') for e in sorted(self.employees.values(), key=lambda e: e.employee_id)],
                        events=[e.model_dump(mode='json') for e in sorted(self.events.values(), key=lambda e: e.event_id)],
                        skills=[s.model_dump(mode='json') for s in sorted(self.skills.values(), key=lambda s: s.skill_id)],
                        role_profiles=[r.model_dump(mode='json') for _, r in sorted(self.roles.items())],
                        activity_history=[r.model_dump(mode='json') for r in sorted(self.activities, key=lambda r: r.record_id)])
        self.revision = hashlib.sha256(json.dumps(self.raw, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]

    @staticmethod
    def _index(model, rows, field):
        result = {}
        for row in rows:
            obj = model.model_validate(row)
            key = getattr(obj, field)
            if key in result:
                raise ValueError(f'Duplicate {field}: {key}')
            result[key] = obj
        return result

    def _validate(self):
        known = self.skills.keys()
        if not self.roles or not self.employees:
            raise ValueError('Dataset must contain employees and role profiles')
        for r in self.roles.values():
            if not r.required_skills.keys() <= known or not set(r.critical_skills) <= r.required_skills.keys():
                raise ValueError(f'Invalid skill references in role {r.role}/{r.grade}')
        for e in self.employees.values():
            if (e.role, e.grade) not in self.roles or not e.skills.keys() <= known:
                raise ValueError(f'Invalid role/skills for {e.employee_id}')
            if e.career_goal and (e.career_goal.target_role, e.career_goal.target_grade) not in self.roles:
                raise ValueError(f'Unknown career goal for {e.employee_id}')
            if e.manager_id and e.manager_id not in self.employees:
                raise ValueError(f'Unknown manager for {e.employee_id}')
            if e.manager_id:
                manager = self.employees[e.manager_id]
                if e.manager_id == e.employee_id or manager.grade != 'Lead' or manager.department != e.department:
                    raise ValueError(f'Invalid manager relationship for {e.employee_id}')
            if e.hire_date > self.as_of or e.last_review_date > self.as_of:
                raise ValueError(f'Future profile date for {e.employee_id}')
            if e.last_review_date < e.hire_date:
                raise ValueError(f'Review before hiring for {e.employee_id}')
        role_names = {r.role for r in self.roles.values()}
        for event in self.events.values():
            refs = set(event.prerequisites) | {g.skill_id for g in event.develops_skills}
            if not refs <= known or not set(event.target_roles) <= role_names:
                raise ValueError(f'Invalid references in {event.event_id}')
            if len({g.skill_id for g in event.develops_skills}) != len(event.develops_skills):
                raise ValueError(f'Duplicate gains in {event.event_id}')
        completed = set()
        for row in self.activities:
            if row.employee_id not in self.employees or row.event_id not in self.events:
                raise ValueError(f'Unknown employee/event in {row.record_id}')
            if row.date > self.as_of:
                raise ValueError(f'Future history row {row.record_id}')
            if row.date < self.employees[row.employee_id].hire_date:
                raise ValueError(f'Activity before hiring in {row.record_id}')
            if row.due_date and not self.events[row.event_id].mandatory:
                raise ValueError(f'Due date on voluntary event in {row.record_id}')
            if row.status == 'overdue' and (not row.due_date or not self.events[row.event_id].mandatory):
                raise ValueError(f'Overdue requires mandatory assignment and due_date in {row.record_id}')
            key = (row.employee_id, row.event_id)
            if row.status == 'completed':
                if key in completed and row.event_id != 'EV_036':
                    self.warnings.append(row.event_id)
                completed.add(key)

    @classmethod
    def from_directory(cls, directory: Path):
        docs = {n: json.loads((directory / f'{n}.json').read_text(encoding='utf-8-sig'))
                for n in ('employees', 'events', 'skills')}
        dates = {d['meta']['as_of_date'] for d in docs.values()}
        if len(dates) != 1:
            raise ValueError('Dataset snapshot dates disagree')
        with (directory / 'activity_history.csv').open(encoding='utf-8-sig', newline='') as f:
            history = [{k: (None if v == '' and k in ('due_date', 'score', 'feedback_rating') else v)
                        for k, v in r.items()} for r in csv.DictReader(f)]
        return cls(dict(as_of_date=dates.pop(), employees=docs['employees']['employees'],
                        events=docs['events']['events'], skills=docs['skills']['skills'],
                        role_profiles=docs['skills']['role_profiles'], activity_history=history))

    def summary(self):
        warnings = []
        if self.warnings:
            warnings.append(dict(code='repeated_completions', count=len(self.warnings),
                event_ids=sorted(set(self.warnings)),
                message='В истории есть повторные завершения мероприятий, хотя README разрешает повтор '
                        'только EV_036. Исходные записи сохранены. Правило обработки нужно уточнить перед расчётом рекомендаций.'))
        return dict(as_of_date=self.as_of.isoformat(), revision=self.revision,
                    employees=len(self.employees), events=len(self.events), skills=len(self.skills),
                    role_profiles=len(self.roles), activities=len(self.activities),
                    files=[dict(name=name, description=description, records=records) for name, description, records in [
                        ('employees.json', 'Профили сотрудников', len(self.employees)),
                        ('events.json', 'Каталог мероприятий', len(self.events)),
                        ('skills.json', 'Навыки и требования ролей', len(self.skills)),
                        ('activity_history.csv', 'История участия', len(self.activities))]],
                    synthetic=True, integrity='validated_with_warnings' if self.warnings else 'validated',
                    warnings=warnings)
