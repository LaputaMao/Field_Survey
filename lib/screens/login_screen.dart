import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_survey/config/api_config.dart';

import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  // 请注意：如果你在Android模拟器上跑，本地电脑后端的IP应该是 10.0.2.2
  // 如果是真机调试，请写你电脑所在的局域网IP
  final String _loginUrl = ApiConfig.loginUrl;

  Future<void> _login() async {
    String username = _usernameController.text.trim();
    String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('用户名或密码不能为空')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse(_loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // 登录成功，保存 Token
        String token = responseData['token'];
        String username = responseData['user']['username'] ?? "默认用户";
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('username', username);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('欢迎回来，$username！')));

        // Navigator.pushReplacementNamed(context, '/home');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      } else {
        // 展示后端返回的错误信息 ("权限不足" 或 "用户名密码错误")
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['error'] ?? '登录失败')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络错误：$e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.eco, size: 80, color: Colors.green), // 占位Logo
              SizedBox(height: 20),
              Text(
                '野外调查APP',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 48),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              SizedBox(height: 24),
              _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green, // 环保主题色
                      ),
                      child: Text(
                        '登 录',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
