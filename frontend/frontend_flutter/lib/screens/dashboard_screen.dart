import 'package:flutter/material.dart';
import '../services/dashboard_service.dart';
import '../models/dashboard_summary.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _service = DashboardService();
  late Future<DashboardSummary> _futureSummary;

  @override
  void initState() {
    super.initState();
    _futureSummary = _service
        .fetchDashboardSummary()
        .then((data) => DashboardSummary.fromJson(data));
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 3,
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tableau de bord RH")),
      body: FutureBuilder<DashboardSummary>(
        future: _futureSummary,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
                child: Text("Erreur: ${snapshot.error}",
                    style: const TextStyle(color: Colors.red)));
          } else if (snapshot.hasData) {
            final summary = snapshot.data!;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Statistiques principales
                  _buildStatCard("Total utilisateurs",
                      summary.totalUsers.toString(), Colors.blue),
                  _buildStatCard("Personnel actif",
                      summary.activePersonnel.toString(), Colors.green),
                  _buildStatCard("Nouveaux ce mois",
                      summary.newThisMonth.toString(), Colors.orange),

                  const SizedBox(height: 20),
                  const Text("Répartition par âge",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(summary.ageDistribution.toString()),

                  const SizedBox(height: 20),
                  const Text("Situation matrimoniale",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(summary.maritalStatus.toString()),

                  const SizedBox(height: 20),
                  const Text("Répartition par spécialité",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(summary.bySpecialty.toString()),

                  const SizedBox(height: 20),
                  const Text("Derniers arrivés",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ...summary.recentPersonnel.map((p) => ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(p["name"]),
                        subtitle: Text(p["role"]),
                        trailing: Text("${p["joined"]}"),
                      )),

                  const SizedBox(height: 20),
                  const Text("Anniversaires à venir 🎂",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ...summary.upcomingBirthdays.map((b) => ListTile(
                        leading: const Icon(Icons.cake, color: Colors.pink),
                        title: Text(b["name"]),
                        subtitle: Text("Date: ${b["date"]}"),
                        trailing: Text(b["email"] ?? ""),
                      )),
                ],
              ),
            );
          } else {
            return const Center(child: Text("Aucune donnée disponible"));
          }
        },
      ),
    );
  }
}
