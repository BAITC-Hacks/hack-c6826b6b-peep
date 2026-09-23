"""Server-owned capabilities. A client role or an unknown grant confers no access."""
PERMISSIONS = frozenset('''users.read users.manage users.roles users.sessions
employees.read employees.manage employees.assessments employees.goals
reference.manage learning.manage recommendations.manage seasons.manage seasons.publish
economy.manage economy.publish pass.manage quests.manage achievements.manage streaks.manage
leaderboards.manage reviews.manage corrections.manage shop.manage stock.manage rewards.fulfill
budgets.manage content.manage branding.manage ai.manage settings.manage audit.read exports.create
system.maintain'''.split())
SENSITIVE = frozenset('users.roles users.sessions corrections.manage economy.publish settings.manage system.maintain'.split())
DEFAULTS = {
    'employee': frozenset(),
    'hr': frozenset('employees.read reviews.manage rewards.fulfill'.split()),
    'admin': PERMISSIONS - SENSITIVE,
    'super_admin': PERMISSIONS,
}


def capabilities(role, grants=()):
    return sorted(DEFAULTS.get(role, frozenset()) | (set(grants) & PERMISSIONS))
