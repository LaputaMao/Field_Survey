import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('主控面板'),
        backgroundColor: Colors.green,
      ),
      body: Center(
        child: Text('欢迎使用环探助手！这是将来的工作台。'),
      ),
    );
  }
}
