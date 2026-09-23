"""Explicit allowlisted administrative commands; never a table/SQL editor."""
from typing import Annotated, Literal
from urllib.parse import urlparse
from pydantic import BaseModel, ConfigDict, Field, model_validator, field_validator

class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)

class Revision(Input):
    expected_revision: int = Field(ge=0, strict=True)

class Reason(Revision):
    reason: str = Field(min_length=3, max_length=2000)

class UserCreate(Reason):
    username: str = Field(pattern=r'^[a-z0-9][a-z0-9._-]{2,79}$')
    display_name: str = Field(min_length=1, max_length=150)
    employee_id: str | None = None
    password: str = Field(min_length=12, max_length=128)

class UserEdit(Reason):
    display_name: str = Field(min_length=1, max_length=150)
    employee_id: str | None = None

class Access(Reason):
    role: Literal['employee','hr','admin','super_admin']
    active: bool
    permissions: list[str] = Field(default_factory=list, max_length=40)

class PasswordReset(Reason):
    temporary_password: str = Field(min_length=12, max_length=128)

class PasswordChange(Input):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)

class Recommendations(Input):
    strategy: Literal['weighted_coverage','unweighted_coverage'] = 'weighted_coverage'
    max_steps: int = Field(default=3, ge=1, le=10)
    horizon_days: int = Field(default=28, ge=1, le=365)
    budget_weeks: int = Field(default=4, ge=1, le=52)
    utility_weight: float = Field(default=.75, ge=0, le=1)
    duration_weight: float = Field(default=.15, ge=0, le=1)
    format_weight: float = Field(default=.10, ge=0, le=1)
    @model_validator(mode='after')
    def weights(self):
        if abs(self.utility_weight+self.duration_weight+self.format_weight-1)>1e-8:
            raise ValueError('Сумма весов должна равняться 1')
        return self

class Economy(Input):
    daily_xp: int = Field(default=100, ge=0, le=10000)
    bonus_xp: int = Field(default=150, ge=0, le=10000)
    daily_count: int = Field(default=2, ge=1, le=10)
    attempts: int = Field(default=3, ge=1, le=20)
    activity_min: int = Field(default=100, ge=0, le=10000)
    activity_max: int = Field(default=300, ge=1, le=10000)
    activity_multiplier: float = Field(default=2, gt=0, le=100)
    reviews_per_day: int = Field(default=2, ge=1, le=20)
    weekly_days: int = Field(default=5, ge=1, le=7)
    weekly_xp: int = Field(default=250, ge=0, le=10000)
    coin_backing: int = Field(default=100, ge=1, le=10000)
    season_days: int = Field(default=90, ge=1, le=366)
    review_days: int = Field(default=7, ge=1, le=60)
    claim_days: int = Field(default=14, ge=1, le=120)
    order_expiry_days: int = Field(default=7, ge=1, le=90)
    @model_validator(mode='after')
    def ranges(self):
        if self.activity_min>self.activity_max or self.review_days>self.claim_days:
            raise ValueError('Минимум превышает максимум или срок выбора короче проверки')
        return self

class Milestone(Input):
    days: int = Field(ge=1, le=366)
    xp: int = Field(ge=0, le=10000)

class Streaks(Input):
    freezes: int = Field(default=2, ge=0, le=30)
    milestones: list[Milestone] = Field(min_length=1, max_length=30)
    @model_validator(mode='after')
    def unique(self):
        if len({m.days for m in self.milestones}) != len(self.milestones):
            raise ValueError('Пороги серии должны быть уникальны')
        return self

class Leaderboards(Input):
    min_xp: int = Field(default=1000, ge=0, le=1000000)
    min_days: int = Field(default=5, ge=0, le=366)
    prizes: list[Annotated[int, Field(ge=0, le=100000)]] = Field(min_length=1, max_length=20)
    criteria: list[Literal['confirmed_xp','confirmed_activity_count','active_days']] = Field(min_length=1, max_length=3)
    winner_title: str = Field(default='Сотрудник сезона', min_length=1, max_length=150)
    @field_validator('criteria')
    @classmethod
    def unique(cls, v):
        if len(set(v)) != len(v): raise ValueError('Критерии не должны повторяться')
        return v

class Achievement(Input):
    code: str = Field(pattern=r'^[a-z][a-z0-9_]{1,60}$')
    name: str = Field(min_length=1, max_length=150)
    condition: Literal['verified_activities','distinct_skills','active_days']
    threshold: int = Field(ge=1, le=10000)
    xp: int = Field(ge=0, le=10000)
    active: bool = True

class Achievements(Input):
    items: list[Achievement] = Field(max_length=100)
    @model_validator(mode='after')
    def unique(self):
        if len({a.code for a in self.items}) != len(self.items): raise ValueError('Коды должны быть уникальны')
        return self

def safe_url(value):
    if not value or value.startswith('/api/media/'): return value
    parsed=urlparse(value)
    if parsed.scheme not in ('https','http') or not parsed.hostname or parsed.username:
        raise ValueError('Используйте HTTP(S) URL без логина')
    return value

class Branding(Input):
    app_name: str = Field(min_length=1, max_length=80)
    primary: str = Field(pattern=r'^#[0-9a-fA-F]{6}$')
    background: str = Field(pattern=r'^#[0-9a-fA-F]{6}$')
    banner: str = Field(default='', max_length=500)
    logo_url: str = Field(default='', max_length=2000)
    _url = field_validator('logo_url')(safe_url)

class ContentEntry(Input):
    key: Literal['home.title','plan.title','season.title','shop.title','catalog.title','history.title',
                 'profile.title','goal.title','skills.title','simulator.title','passport.title','rules.notice']
    value: str = Field(max_length=4000)
    @field_validator('value')
    @classmethod
    def placeholders(cls, v):
        from string import Formatter
        allowed={'level','xp','coins','season_name'}
        for _, field, spec, conv in Formatter().parse(v):
            if field is not None and (field not in allowed or spec or conv):
                raise ValueError('Недопустимый placeholder')
        return v

class Content(Input):
    locale: Literal['ru','kk','en'] = 'ru'
    entries: list[ContentEntry] = Field(max_length=300)
    @model_validator(mode='after')
    def unique(self):
        if len({e.key for e in self.entries})!=len(self.entries):raise ValueError('Ключи текстов должны быть уникальны')
        return self

class Assistant(Input):
    mode: Literal['environment','template','llm'] = 'environment'
    model: str = Field(default='gpt-4o-mini', pattern=r'^[a-zA-Z0-9._-]{1,80}$')
    timeout_seconds: int = Field(default=8, ge=1, le=30)
    max_output_tokens: int = Field(default=900, ge=200, le=4000)
    secret_alias: Literal['OPENAI_API_KEY'] = 'OPENAI_API_KEY'

class Settings(Input):
    organization: str = Field(min_length=1, max_length=150)
    timezone: Literal['Asia/Almaty','Asia/Qyzylorda','UTC'] = 'Asia/Almaty'
    locale: Literal['ru','kk','en'] = 'ru'
    session_hours: int = Field(default=8, ge=1, le=24)
    preview_minutes: int = Field(default=15, ge=1, le=60)
    maintenance: bool = False
    maintenance_message: str = Field(default='Техническое обслуживание', min_length=3, max_length=500)
    shop_paused: bool = False
    quests_paused: bool = False

class Department(Input):
    id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=150)
    parent_id: str | None = None
    active: bool = True

class Skill(Input):
    skill_id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=150)
    type: Literal['hard','soft'] = 'hard'
    category: str = Field(min_length=1, max_length=100)
    description: str = Field(default='', max_length=4000)
    active: bool = True

class Requirement(Input):
    level: float = Field(gt=0, le=100)
    weight: float = Field(gt=0, le=100)

class CareerRole(Input):
    role_id: str = Field(min_length=1, max_length=100)
    grade_id: str = Field(min_length=1, max_length=100)
    rank: int = Field(default=1, ge=0, le=1000)
    active: bool = True
    requirements: dict[str, Requirement] = Field(min_length=1, max_length=200)

class Activity(Input):
    id: str = Field(min_length=1, max_length=100)
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1, max_length=4000)
    outcome: str = Field(min_length=1, max_length=4000)
    instructions: str = Field(min_length=1, max_length=10000)
    external_url: str = Field(default='', max_length=2000)
    image_url: str = Field(default='', max_length=2000)
    format: Literal['online','offline','self_paced']
    kind: Literal['self_paced','scheduled'] = 'self_paced'
    duration_minutes: int = Field(ge=1, le=100000)
    gains: dict[str, Annotated[float, Field(ge=0, le=20)]]
    prerequisites: dict[str, Annotated[float, Field(ge=0, le=100)]] = Field(default_factory=dict)
    starts_at: str | None = None
    ends_at: str | None = None
    available_from: str | None = None
    available_until: str | None = None
    reward_eligible: bool = True
    active: bool = True
    _urls = field_validator('external_url','image_url')(safe_url)
    @model_validator(mode='after')
    def dates(self):
        from .engine import instant
        for key in ('starts_at','ends_at','available_from','available_until'):
            if getattr(self,key) and instant(getattr(self,key)).tzinfo is None:
                raise ValueError('Дата должна содержать timezone')
        if self.kind=='scheduled' and (not self.starts_at or not self.ends_at or instant(self.starts_at)>=instant(self.ends_at)):
            raise ValueError('Укажите корректный интервал активности')
        return self

class Item(Input):
    id: str = Field(min_length=1, max_length=120)
    name: str = Field(min_length=1, max_length=150)
    category: str = Field(min_length=1, max_length=100)
    description: str = Field(min_length=1, max_length=4000)
    delivery_terms: str = Field(min_length=1, max_length=2000)
    coin_price: int | None = Field(default=None, ge=1, le=100000)
    unit_budget_kzt: int = Field(ge=0, le=10000000)
    shop_visible: bool = True
    active: bool = True
    image_url: str = Field(default='', max_length=2000)
    _url = field_validator('image_url')(safe_url)

class Coins(Input):
    type: Literal['coins']
    coins: int = Field(ge=1, le=100000)
    name: str = Field(min_length=1, max_length=150)

class Gift(Input):
    type: Literal['gift']
    budget_cap_kzt: int = Field(ge=1, le=10000000)
    pool_code: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,60}$')
    name: str = Field(min_length=1, max_length=150)

class Mini(Gift):
    type: Literal['mini']

class Cosmetic(Input):
    type: Literal['cosmetic']
    name: str = Field(min_length=1, max_length=150)
    cosmetic_code: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,60}$')

Component = Annotated[Coins | Gift | Mini | Cosmetic, Field(discriminator='type')]

class PassLevel(Input):
    level: int = Field(ge=1, le=200)
    required_total_xp: int = Field(ge=1, le=10000000)
    components: list[Component] = Field(min_length=1, max_length=10)

class Pass(Input):
    rewards: list[PassLevel] = Field(min_length=1, max_length=200)
    @model_validator(mode='after')
    def sequence(self):
        if [r.level for r in self.rewards] != list(range(1,len(self.rewards)+1)):
            raise ValueError('Уровни должны идти подряд с 1')
        if any(a.required_total_xp>=b.required_total_xp for a,b in zip(self.rewards,self.rewards[1:])):
            raise ValueError('Пороги XP должны строго возрастать')
        pools={}
        for reward in self.rewards:
            for part in reward.components:
                if isinstance(part,Gift):
                    definition=(part.type,part.budget_cap_kzt)
                    if part.pool_code in pools and pools[part.pool_code]!=definition:
                        raise ValueError('Один код пула должен иметь одинаковый тип и лимит')
                    pools[part.pool_code]=definition
        return self

class Pool(Input):
    id: str
    season_id: str
    code: str
    cap: int = Field(ge=1, le=10000000)
    item_ids: list[str] = Field(min_length=1, max_length=500)
    fallback_item_id: str

class QuestField(Input):
    key: str = Field(pattern=r'^[a-z][a-z0-9_]{0,40}$')
    label: str = Field(min_length=1, max_length=150)
    type: Literal['decimal','choice','text']
    options: list[str] = Field(default_factory=list, max_length=20)

class Quest(Input):
    id: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,60}$')
    title: str = Field(min_length=1, max_length=150)
    instructions: str = Field(min_length=1, max_length=4000)
    kind: Literal['generator','structured'] = 'structured'
    generator: Literal['main','bonus'] = 'main'
    answer_fields: list[QuestField] = Field(default_factory=list, max_length=10)
    expected_answer: dict[str,str] = Field(default_factory=dict)
    explanation: str = Field(default='', max_length=3000)
    xp: int = Field(ge=0, le=10000)
    max_attempts: int = Field(default=3, ge=1, le=20)
    weekdays: list[Annotated[int,Field(ge=0,le=6)]] = Field(default_factory=lambda:list(range(7)),min_length=1,max_length=7)
    active: bool = True
    @model_validator(mode='after')
    def answers(self):
        if self.kind=='structured':
            if not self.answer_fields or len({f.key for f in self.answer_fields})!=len(self.answer_fields):
                raise ValueError('Нужны уникальные поля ответа')
            if set(self.expected_answer)!={f.key for f in self.answer_fields}: raise ValueError('Укажите ответ для каждого поля')
            from .game_rules import rounded
            for f in self.answer_fields:
                if f.type=='decimal': self.expected_answer[f.key]=rounded(self.expected_answer[f.key])
                elif f.type=='choice' and self.expected_answer[f.key] not in f.options: raise ValueError('Правильный вариант отсутствует в списке')
        return self

class Quests(Input):
    items: list[Quest] = Field(max_length=100)
    @model_validator(mode='after')
    def unique(self):
        if len({q.id for q in self.items})!=len(self.items):raise ValueError('ID заданий должны быть уникальны')
        return self

class Nomination(Input):
    id: str = Field(pattern=r'^[a-zA-Z0-9_-]{1,60}$')
    name: str = Field(min_length=1,max_length=150)
    criterion: Literal['confirmed_xp','confirmed_activity_count','active_days','best_streak','distinct_skills']
    per_department: bool = False
    coins: int = Field(ge=0,le=100000)
    active: bool = True

class Nominations(Input):
    items: list[Nomination] = Field(max_length=30)
    @model_validator(mode='after')
    def unique(self):
        if len({n.id for n in self.items})!=len(self.items):raise ValueError('ID номинаций должны быть уникальны')
        return self

class PlanAction(Reason):
    action: Literal['add','archive','replace','reorder']
    activity_id: str | None = None
    plan_id: str | None = None
    item_ids: list[str] = Field(default_factory=list,max_length=10)
    accept_no_goal_gain: bool = False
    accept_over_budget: bool = False

class SeasonMembers(Reason):
    employee_ids: list[str] = Field(min_length=1,max_length=10000)

class SeasonEdit(Reason):
    name: str = Field(min_length=1,max_length=150)
    starts_at: str
    ends_at: str
    @field_validator('starts_at','ends_at')
    @classmethod
    def date_valid(cls,v):
        from .engine import instant
        if instant(v).tzinfo is None:raise ValueError('Укажите часовой пояс')
        return v

class Revalue(Input):
    type: Literal['revalue']
    season_id: str
    coin_backing: int = Field(ge=1,le=10000)

class Recalculate(Input):
    type: Literal['recalculate_results']
    season_id: str
    retain_prior_prizes: Literal[True] = True

class AssessmentCorrection(Input):
    type: Literal['assessment']
    employee_id: str
    assessed_at: str
    skills: dict[str,Annotated[float,Field(ge=0,le=100)]] = Field(min_length=1)
    @field_validator('assessed_at')
    @classmethod
    def date_valid(cls,v):
        from .engine import instant
        if instant(v).tzinfo is None:raise ValueError('Укажите часовой пояс')
        return v

class ReviewCorrection(Input):
    type: Literal['review']
    source_id: str
    decision: Literal['approved','rejected']

class GiftCorrection(Input):
    type: Literal['gift']
    employee_id: str
    season_id: str
    pool_id: str
    name: str = Field(min_length=1,max_length=150)

class DeliveryCorrection(Input):
    type: Literal['reverse_delivery']
    source_id: str
    returned_to_stock: Literal[True]

class RecommendationTest(Input):
    employee_id: str
    payload: Recommendations

class AssistantTest(Input):
    employee_id: str
    payload: Assistant

class Employee(Input):
    id: str = Field(min_length=1, max_length=100)
    full_name: str = Field(min_length=1, max_length=150)
    department: str = Field(min_length=1, max_length=150)
    role: str = Field(min_length=1, max_length=100)
    grade: str = Field(min_length=1, max_length=100)
    active: bool = True

class Assessment(Reason):
    assessed_at: str
    skills: dict[str, Annotated[float, Field(ge=0, le=100)]] = Field(min_length=1)
    source: str = Field(min_length=1, max_length=200)
    @field_validator('assessed_at')
    @classmethod
    def date_valid(cls,v):
        from .engine import instant
        if instant(v).tzinfo is None:raise ValueError('Укажите часовой пояс')
        return v

class Goal(Reason):
    kind: Literal['personal','profile'] = 'personal'
    role_id: str
    grade_id: str
    confirm_archive_plan: bool = False

class Inventory(Reason):
    item_id: str
    delta: int = Field(ge=-100000, le=100000)

class Budget(Reason):
    season_id: str
    amount_kzt: int = Field(ge=1, le=100000000000)

class Season(Reason):
    name: str = Field(min_length=1, max_length=150)
    starts_at: str
    employee_ids: list[str] = Field(min_length=1, max_length=10000)
    virtual_budget_kzt: int = Field(ge=0)
    @field_validator('starts_at')
    @classmethod
    def date_valid(cls,v):
        from .engine import instant
        if instant(v).tzinfo is None:raise ValueError('Укажите часовой пояс')
        return v

class Publish(Reason):
    preview_id: str

class CorrectionAction(Input):
    type: Literal['xp','coins','restore_attempt']
    employee_id: str
    season_id: str
    delta: int = Field(ge=-1000000, le=1000000)
    source_id: str = Field(default='', max_length=300)

class XPAdjustment(CorrectionAction):
    type: Literal['xp']

class CoinAdjustment(CorrectionAction):
    type: Literal['coins']

class RestoreAttempt(CorrectionAction):
    type: Literal['restore_attempt']

class Correction(Revision):
    reason: str = Field(min_length=20, max_length=2000)
    actions: list[Annotated[XPAdjustment | CoinAdjustment | RestoreAttempt | Revalue | Recalculate | AssessmentCorrection | ReviewCorrection | GiftCorrection | DeliveryCorrection,Field(discriminator='type')]] = Field(min_length=1, max_length=100)

POLICY_MODELS = dict(recommendations=Recommendations, economy=Economy, streaks=Streaks,
                     leaderboards=Leaderboards, achievements=Achievements, branding=Branding,
                     content=Content, assistant=Assistant, settings=Settings,quests=Quests,nominations=Nominations)
ENTITY_MODELS = dict(departments=Department, skills=Skill, **{'career-roles':CareerRole},
                     activities=Activity, shop=Item, **{'reward-pools':Pool}, employees=Employee, **{'pass':Pass})
