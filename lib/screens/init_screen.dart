import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';
import 'home_screen.dart';
import 'package:field_survey/config/api_config.dart';


class InitScreen extends StatefulWidget {
  @override
  _InitScreenState createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  // 注意保持 IP 为你的后端地址
  final String _verifyUrl = ApiConfig.verifyTokenUrl;

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  Future<void> _checkToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');

    if (token == null || token.isEmpty) {
      // 没登录过，直接去登录页
      _navigateToLogin();
      return;
    }

    // 有 Token，向后端校验
    try {
      final response = await http
          .get(
            Uri.parse(_verifyUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token', // 携带 Bearer Token
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Token 有效，跳过登录页直接进主页
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      } else {
        // Token 失效、过期（401 等）
        await prefs.remove('jwt_token'); // 清理作废的 token
        _showExpiredDialog();
      }
    } catch (e) {
      // 网络异常（例如没网、超时）
      // 野外工具APP考虑：如果没有网，但本地有token，你可能需要允许离线登录(后续优化点)
      // 现在我们暂且把它当做失效或者让用户再试一次
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('网络连接不可用，将前往登录界面: $e')));
        _navigateToLogin();
      }
    }
  }

  void _showExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // 强制用户必须点击
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('登录状态失效'),
          content: Text('您的登录状态已过期或失效，请重新登录。'),
          actions: <Widget>[
            TextButton(
              child: Text('好', style: TextStyle(color: Colors.green)),
              onPressed: () {
                Navigator.of(context).pop(); // 关闭对话框
                _navigateToLogin(); // 返回登录页
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 这里其实用户不会看太久，为了不突兀，显示一个绿色的载入圈加上LOGO
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon(Icons.eco, size: 80, color: Colors.green),
            Image.asset(
              'assets/logo.png',
              width: 80,  // 对应原来图标的 size 宽度
              height: 80, // 对应原来图标的 size 高度
              fit: BoxFit.contain, // 保证你的 Logo 比例不会变形
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.green),
            SizedBox(height: 16),
            Text('正在验证身份...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
