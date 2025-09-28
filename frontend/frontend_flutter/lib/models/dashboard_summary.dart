class DashboardSummary {
  final int totalUsers;
  final int activePersonnel;
  final int newThisMonth;
  final Map<String, dynamic> ageDistribution;
  final Map<String, dynamic> maritalStatus;
  final Map<String, dynamic> bySpecialty;
  final List<dynamic> recentPersonnel;
  final List<dynamic> upcomingBirthdays;

  DashboardSummary({
    required this.totalUsers,
    required this.activePersonnel,
    required this.newThisMonth,
    required this.ageDistribution,
    required this.maritalStatus,
    required this.bySpecialty,
    required this.recentPersonnel,
    required this.upcomingBirthdays,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      totalUsers: json["total_users"],
      activePersonnel: json["active_personnel"],
      newThisMonth: json["new_this_month"],
      ageDistribution: json["age_distribution"],
      maritalStatus: json["marital_status"],
      bySpecialty: json["by_specialty"],
      recentPersonnel: json["recent_personnel"],
      upcomingBirthdays: json["upcoming_birthdays"],
    );
  }
}
