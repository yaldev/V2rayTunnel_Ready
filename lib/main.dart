import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray_client.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'database_helper.dart';
import 'api_service.dart';
import 'config_generator.dart';
import 'server_list_screen.dart';
import 'custom_server_screen.dart';

void main() {
  runApp(const V2RayTunnelApp());
}

class V2RayTunnelApp extends StatelessWidget {
  const V2RayTunnelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V2Ray Tunnel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF00BFFF),
        scaffoldBackgroundColor: const Color(0xFFF0F8FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFFF),
          primary: const Color(0xFF00BFFF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isConnected = false;
  String timerText = "00:00:00";
  int _currentIndex = 0;
  bool _isLoading = true;
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  String _formatTime(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return "${hours.toString().padLeft(2, '0')}:"
        "${minutes.toString().padLeft(2, '0')}:"
        "${seconds.toString().padLeft(2, '0')}";
  }

  Future<void> _initApp() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      await DatabaseHelper().initializeSession();
      await ApiService().loadStaticServers();
      await ApiService().loadNetworks();
      await ApiService().fetchKeysFromGitHub();

      // Initialize Unity Ads with real Game ID and testMode: false
      await UnityAds.init(
        gameId: '800439380',
        testMode: false,
        onComplete: () {
          if (!mounted) return;
          _loadRewardedAd();
        },
        onFailed: (error, message) {
          print('UnityAds init failed: $error $message');
        },
      );

      // Initialize V2Ray Core with correct provider bundle identifier matching package name
      await FlutterV2ray.initialize(
        notificationIconResourceName: "ic_launcher",
        notificationIconResourceType: "mipmap",
        providerBundleIdentifier: "com.example.v2raytunnel",
      );

      // Request VPN Permission
      await FlutterV2ray.requestPermission();

      // Fetch initial time from DB
      int savedSeconds = await DatabaseHelper().getRemainingTime();
      if (!mounted) return;
      setState(() {
        _remainingSeconds = savedSeconds;
        timerText = _formatTime(_remainingSeconds);
      });

      // Status listener
      FlutterV2ray.onStatusChanged.listen((status) {
        if (!mounted) return;
        setState(() {
          isConnected = status.state == 'CONNECTED';
          if (!isConnected) {
            _stopTimer();
          }
        });
      });
    } catch (e) {
      print('Initialization error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadRewardedAd() {
    UnityAds.load(
      placementId: 'BP_Rewarded_Android',
      onComplete: (placementId) {
        if (!mounted) return;
        setState(() => _isAdLoaded = true);
      },
      onFailed: (placementId, error, message) {
        if (!mounted) return;
        setState(() => _isAdLoaded = false);
      },
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_remainingSeconds > 0) {
        if (!mounted) return;
        setState(() {
          _remainingSeconds--;
          timerText = _formatTime(_remainingSeconds);
        });

        // Every 10 seconds, update the DB
        if (_remainingSeconds % 10 == 0) {
          await DatabaseHelper().updateRemainingTime(_remainingSeconds);
        }
      } else {
        // Time expired
        _timer?.cancel();
        try {
          await FlutterV2ray.stopV2ray();
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          isConnected = false;
          timerText = "00:00:00";
        });
        await DatabaseHelper().updateRemainingTime(0);
        _showSnackBar("Time expired. Watch an ad to continue.");
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  Future<void> _onStartStopPressed() async {
    if (isConnected) {
      try {
        await FlutterV2ray.stopV2ray();
        if (!mounted) return;
        setState(() {
          isConnected = false;
        });
        _stopTimer();
      } catch (e) {
        _showSnackBar("Error stopping VPN: $e");
      }
    } else {
      if (_remainingSeconds <= 0) {
        if (!_isAdLoaded) {
          _showSnackBar("Ad not ready, wait...");
          _loadRewardedAd();
          return;
        }

        UnityAds.show(
          placementId: 'BP_Rewarded_Android',
          onComplete: (placementId) async {
            if (!mounted) return;
            setState(() {
              _isAdLoaded = false;
              _remainingSeconds = 21600; // 6 hours
              timerText = _formatTime(_remainingSeconds);
            });
            await DatabaseHelper().updateRemainingTime(21600);
            _loadRewardedAd();
            _connectVpn();
          },
          onFailed: (placementId, error, message) {
            if (!mounted) return;
            _showSnackBar("Ad failed to show: $message");
            _loadRewardedAd();
          },
          onSkipped: (placementId) {
            if (!mounted) return;
            _showSnackBar("Ad was skipped. You must watch the ad to get connection time.");
            _loadRewardedAd();
          },
        );
      } else {
        _connectVpn();
      }
    }
  }

  Future<void> _connectVpn() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00BFFF),
        ),
      ),
    );

    try {
      final fastestKey = await DatabaseHelper().getFastestKey();
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      if (fastestKey == null || fastestKey['ip'] == null || (fastestKey['ip'] as String).isEmpty) {
        _showSnackBar("No active VPN keys available. Please check connection.");
        return;
      }

      String uuidOrPass = fastestKey['uuid_or_pass'] ?? '';
      String path = fastestKey['path'] ?? '/';
      String ipAddress = fastestKey['ip'] ?? '';
      int port = fastestKey['port'] ?? 443;
      String protocol = fastestKey['protocol'] ?? 'vless';
      String security = fastestKey['security'] ?? 'tls';
      String type = fastestKey['type'] ?? 'ws';
      
      String hostSni = "firebase.google.com";
      String name = "V2Ray Tunnel Auto";

      List<Map<String, dynamic>> networks = await DatabaseHelper().getAllNetworks();
      if (networks.isNotEmpty) {
        hostSni = networks.first['host'] ?? hostSni;
        name = "${networks.first['country']} - ${networks.first['isp']}";
      }

      String uri = '';
      if (protocol == 'trojan') {
        uri = ConfigGenerator.generateTrojan(password: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: hostSni, name: name, security: security, type: type);
      } else if (protocol == 'vmess') {
        uri = ConfigGenerator.generateVmess(uuid: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: hostSni, name: name, security: security, type: type);
      } else {
        uri = ConfigGenerator.generateVless(uuid: uuidOrPass, path: path, ipAddress: ipAddress, port: port, hostSni: hostSni, name: name, security: security, type: type);
      }

      await FlutterV2ray.startV2ray(
        remark: name,
        config: uri,
        blockedApps: null,
        bypassSubnets: null,
      );

      if (!mounted) return;
      setState(() {
        isConnected = true;
      });
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showSnackBar("Failed to start VPN: $e");
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00BFFF),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {},
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "V2Ray Tunnel",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "🇲🇦 -> IAM -> 104.18.37.127",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Color(0xFF00BFFF),
                  ),
                  SizedBox(height: 16),
                  Text(
                    "Initializing VPN & Servers...",
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Ad Banner Placeholder
                  Container(
                    height: 60,
                    width: double.infinity,
                    color: Colors.grey[400],
                    alignment: Alignment.center,
                    child: const Text(
                      "Unity Ads Banner Placeholder",
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 1: Server Selection
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.add_circle,
                          color: Color(0xFF00BFFF),
                          size: 28,
                        ),
                        title: const Text(
                          "Auto Select Server",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.language,
                          color: Color(0xFF00BFFF),
                          size: 28,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ServerListScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Card 2: Custom Host (Watch Ad)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.video_call,
                          color: Colors.amber,
                          size: 28,
                        ),
                        title: const Text(
                          "Custom Host (Watch Ad)",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CustomServerScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Data Stats Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const Column(
                          children: [
                            Icon(
                              Icons.cloud_download,
                              color: Color(0xFF00BFFF),
                              size: 28,
                            ),
                            SizedBox(height: 6),
                            Text(
                              "Download\n0 KB",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          height: 40,
                          width: 1,
                          color: Colors.grey[300],
                        ),
                        const Column(
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              color: Color(0xFF00BFFF),
                              size: 28,
                            ),
                            SizedBox(height: 6),
                            Text(
                              "Upload\n0 KB",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Connection Status
                  Column(
                    children: [
                      Text(
                        isConnected ? "Connected" : "Disconnected",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isConnected ? Colors.green : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timerText,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00BFFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),

                  // Main START/STOP Button
                  GestureDetector(
                    onTap: _onStartStopPressed,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: const Color(0xFF00BFFF),
                          width: 6,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00BFFF).withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          isConnected ? "STOP" : "START",
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00BFFF),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF00BFFF),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            label: "Update",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.send),
            label: "Join Us",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.exit_to_app),
            label: "EXIT",
          ),
        ],
      ),
    );
  }
}
