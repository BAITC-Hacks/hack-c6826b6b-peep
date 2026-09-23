"""Employee-facing source profile, with private goals kept separate."""
GRADES = ['Junior', 'Middle', 'Senior', 'Lead']


def profile(dataset, employee_id, personal_goal=None):
    employee = dataset.employees[employee_id]
    source_goal = employee.career_goal.model_dump(mode='json') if employee.career_goal else None
    goal = personal_goal or source_goal
    suggestion = None
    if goal is None:
        index = GRADES.index(employee.grade)
        for grade in GRADES[index + 1:]:
            if (employee.role, grade) in dataset.roles:
                suggestion = dict(target_role=employee.role, target_grade=grade)
                break
    source = 'personal' if personal_goal else 'dataset' if source_goal else 'suggested' if suggestion else 'none'
    display_goal = goal or suggestion
    target = dataset.roles.get((display_goal['target_role'], display_goal['target_grade'])) if display_goal else None
    required = target.required_skills if target else {}
    skills = []
    for sid in set(employee.skills) | set(required):
        skill = dataset.skills[sid]
        skills.append(dict(skill_id=sid, name=skill.name, type=skill.type, category=skill.category,
                           assessed_level=employee.skills.get(sid, 0), required_level=required.get(sid),
                           critical=bool(target and sid in target.critical_skills)))
    skills.sort(key=lambda s: (not s['critical'], s['type'], s['name']))
    history = []
    for row in reversed(dataset.by_employee[employee_id]):
        event = dataset.events[row.event_id]
        history.append(dict(**row.model_dump(mode='json'), title=event.title, type=event.type, mandatory=event.mandatory))
    return dict(employee=employee.model_dump(mode='json'), goal=goal, suggested_goal=suggestion,
                goal_source=source, skills=skills, history=history,
                stats=dict(total=len(history), completed=sum(h['status'] == 'completed' for h in history),
                           in_progress=sum(h['status'] == 'in_progress' for h in history),
                           mandatory_pending=sum(h['mandatory'] and h['status'] != 'completed' for h in history)),
                calculation=dict(status='not_calculated'))
