import 'package:flutter/material.dart';

class HoldToCompleteButton extends StatefulWidget {
  final VoidCallback onCompleted;

  const HoldToCompleteButton({Key? key, required this.onCompleted})
    : super(key: key);

  @override
  _HoldToCompleteButtonState createState() => _HoldToCompleteButtonState();
}

class _HoldToCompleteButtonState extends State<HoldToCompleteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 长按 1.5 秒触发完成
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    );
    _controller.addListener(() {
      setState(() {});
      if (_controller.value == 1.0) {
        // 动画满了，触发完成回调
        widget.onCompleted();
        _controller.reset(); // 触发后重置
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(), // 按下开始填充进度条
      onTapUp: (_) => _controller.reverse(), // 松开倒退进度条
      onTapCancel: () => _controller.reverse(), // 移出区域倒退
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 背景圆圈(红色结束)
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.stop, color: Colors.white, size: 30),
          ),
          // 外围的进度条动画
          SizedBox(
            width: 68,
            height: 68,
            child: CircularProgressIndicator(
              value: _controller.value,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
              strokeWidth: 4,
            ),
          ),
        ],
      ),
    );
  }
}
