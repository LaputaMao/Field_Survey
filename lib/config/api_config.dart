class ApiConfig {
  // ⭐ 以后只需要改这一个地方
  // 模拟器调试用 10.0.2.2，真机调试用 cpolar 生成的公网地址
  // tip static const String baseUrl = 'http://10.0.2.2:9096/api/v1';
  static const String baseUrl = 'https://35e45961.r32.cpolar.top/api/v1';

  // 拼接所有的 Endpoints
  static const String loginUrl = '$baseUrl/login';
  static const String verifyTokenUrl = '$baseUrl/verify-token';
  //static const String taskUrl = '$baseUrl/tasks'; // 假设你的任务接口
}
