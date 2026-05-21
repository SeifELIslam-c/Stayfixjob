class UserModel {
  final String name;
  final String email;
  final String phone;
  final String age;
  final String jobTitle;
  final String department;
  final String maintenanceType;
  final List<String> specialties;

  UserModel({
    required this.name,
    required this.email,
    required this.phone,
    required this.age,
    required this.jobTitle,
    this.department = '',
    this.maintenanceType = '',
    this.specialties = const [],
  });
}
