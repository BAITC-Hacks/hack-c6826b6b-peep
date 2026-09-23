"""Typed schemas for source data, authenticated sessions and validated imports."""
from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Level = Annotated[int, Field(ge=0, le=5, strict=True)]
Identifier = Annotated[str, Field(pattern=r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$')]
Grade = Literal['Junior', 'Middle', 'Senior', 'Lead']


class Model(BaseModel):
    model_config = ConfigDict(extra='forbid')


class Goal(Model):
    target_role: str
    target_grade: Grade


class Employee(Model):
    employee_id: Identifier
    full_name: str
    department: str
    role: str
    grade: Grade
    manager_id: Identifier | None
    hire_date: date
    tenure_months: int = Field(ge=0, strict=True)
    work_format: Literal['office', 'hybrid', 'remote']
    preferred_language: Literal['kk', 'ru', 'en']
    career_goal: Goal | None
    skills: dict[str, Level]
    last_review_date: date


class Skill(Model):
    skill_id: Identifier
    name: str
    type: Literal['hard', 'soft']
    category: str
    description: str


class Role(Model):
    role: str
    grade: Grade
    required_skills: dict[str, Level]
    critical_skills: list[str]


class Gain(Model):
    skill_id: Identifier
    gain: int = Field(gt=0, le=5, strict=True)
    max_level: Level


class Event(Model):
    event_id: Identifier
    title: str
    description: str
    type: Literal['compliance', 'onboarding', 'course', 'workshop', 'mentoring', 'certification', 'meetup']
    format: Literal['online', 'offline', 'self_paced']
    duration_hours: float = Field(gt=0, le=10000, allow_inf_nan=False)
    mandatory: bool
    target_roles: list[str]
    target_grades: list[Grade]
    develops_skills: list[Gain]
    prerequisites: dict[str, Level]
    upcoming_sessions: list[date]


class Activity(Model):
    record_id: Identifier
    employee_id: Identifier
    event_id: Identifier
    date: date
    due_date: date | None = None
    status: Literal['completed', 'in_progress', 'dropped', 'no_show', 'declined', 'overdue']
    completion_pct: int = Field(ge=0, le=100)
    score: int | None = Field(default=None, ge=0, le=100)
    feedback_rating: int | None = Field(default=None, ge=1, le=5)
    assigned_by: Literal['self', 'manager', 'hr']

    @model_validator(mode='after')
    def complete_means_complete(self):
        if self.status == 'completed' and self.completion_pct != 100:
            raise ValueError('completed requires completion_pct=100')
        if self.status != 'completed' and self.completion_pct == 100:
            raise ValueError('100% requires completed status')
        if self.status in ('declined', 'no_show') and self.completion_pct != 0:
            raise ValueError('declined/no_show require completion_pct=0')
        return self


class LoginRequest(Model):
    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=200)


class CommitRequest(Model):
    preview_id: str = Field(min_length=1, max_length=100)
