import 'dart:io';
import 'database_helper.dart';

class PingService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<void> checkAllServers() async {
    try {
      List<Map<String, dynamic>> servers = await _dbHelper.getAllServers();

      for (var server in servers) {
        int id = server['id'];
        String ip = server['ip'] ?? '';
        int port = server['port'] ?? 443;
        int failureCount = server['failure_count'] ?? 0;

        if (ip.isEmpty) continue;

        Stopwatch stopwatch = Stopwatch()..start();
        try {
          Socket socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 2));
          stopwatch.stop();
          int pingMs = stopwatch.elapsedMilliseconds;
          await socket.close();

          // Successful connection
          await _dbHelper.updateServerStatus(id, 1, pingMs, 0);
        } catch (e) {
          // Failed connection
          await _dbHelper.updateServerStatus(id, 0, 0, failureCount + 1);
        }
      }

      // Delete dead servers
      await _dbHelper.deleteDeadServers();
    } catch (e) {
      print('Error checking servers: $e');
    }
  }
}
