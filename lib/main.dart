// lib/main.dart
import 'package:field_survey/screens/init_screen.dart';
import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '环探助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: InitScreen(), // 指定入口为欢迎页
    );
  }
}
