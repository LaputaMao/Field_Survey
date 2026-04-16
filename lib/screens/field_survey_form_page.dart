import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_survey/config/api_config.dart';
import 'package:proj4dart/proj4dart.dart';
import 'dart:math' as math;

class FieldSurveyFormPage extends StatefulWidget {
  final LatLng currentGps; // 传入GPS位置
  final int taskId; // 整型的 taskId
  final String pathId; // 原本的 routeId 改叫 pathId
  final String templateType; // 接收模板类型
  final String? autoScreenshotPath; // 可选的系统截图路径
  // ⭐ 新增参数：用于编辑模式
  final String? editPointId; // 如果不为null，说明是编辑老点
  final Map<String, dynamic>? initialData; // 从后端拉回的老表单数据大JSON

  const FieldSurveyFormPage({
    Key? key,
    required this.currentGps,
    required this.taskId, // 必传
    required this.pathId, // 必传
    required this.templateType,
    this.autoScreenshotPath, //加入构造器
    this.editPointId,
    this.initialData,
  }) : super(key: key);

  @override
  _FieldSurveyFormPageState createState() => _FieldSurveyFormPageState();
}

// 定义照片列表和表单数据的统一存储
class _FieldSurveyFormPageState extends State<FieldSurveyFormPage> {
  // 一个大 Map，用于在内存里装载所有用户填写的、自动生成的数据
  final Map<String, dynamic> _formData = {};

  // tip 二级下拉数据结构
  //地貌部位
  final Map<String, List<String>> _geomorphic = {
    "丘陵山地起伏地形": ["坡顶(顶部)", "坡上(上部)", "坡中(中部)", "坡下(下部)", "坡麓(底部)"],
    "平原或平坦地形": [
      "高阶地(洪－冲积平原)",
      "低阶地(河流冲积平原)",
      "河漫滩",
      "底部(排水线)",
      "潮上带",
      "潮间带",
      "其他",
    ],
  };

  //土地利用类型
  final Map<String, List<String>> _landUse = {
    "湿地": ["森林沼泽", "灌丛沼泽", "沼泽草地", "沼泽地", "内陆滩涂"],
    "耕地": ["水田", "水浇地", "旱地"],
    "园地": ["果园", "茶园", "其他园地"],
    "林地": ["乔木林地", "竹林地", "灌木林地", "其他林地"],
    "草地": ["天然牧草地", "人工牧草地", "其他草地"],
    "商业服务业用地": ["其他城镇用地"],
    "工矿用地": ["其他城镇用地"],
    "住宅用地": ["住宅用地"],
    "公共管理与公共服务用地": ["其他城镇用地"],
    "特殊用地": ["其他城镇用地"],
    "交通运输用地": ["其他城镇用地"],
    "水域及水利设施用地": ["河流水面", "湖泊水面", "水库水面", "坑塘水面", "沟渠", "冰川及永久积雪"],
    "其他土地": ["裸岩石砾地", "裸土地", "盐碱地", "沙地"],
  };

  //生态系统类型
  final Map<String, List<String>> _ecosystem = {
    "森林生态系统": ["阔叶林", "针叶林", "针阔混交林", "竹林", "灌木林", "其他林地"],
    "草地生态系统": ["草甸", "草原", "草丛", "高寒稀疏植被与冻原", "人工（栽培）草地"],
    "湿地生态系统": ["沼泽", "河流", "湖泊"],
    "农田生态系统": ["耕地", "园地"],
    "荒漠生态系统": ["荒漠"],
    "城镇生态系统": ["城镇"],
    "冰川及永久积雪": ["冰川及永久积雪"],
    "裸地": ["裸地"],
  };

  //生态问题类型
  final Map<String, List<String>> _ecoProblem = {
    "土地退化": ["水土流失型（水力侵蚀）", "沙化型", "石漠化型", "冻融型", "盐渍化型"],
    "生境退化": ["生境破碎化", "区域地下水位下降显著"],
    "生态系统退化": ["森林退化", "草地退化", "湿地退化", "冰川退缩", "多年冻土消融"],
    "生态系统服务退化": ["水土保持", "水源涵养", "防风固沙", "固碳"],
  };

  //成土母岩岩性
  final Map<String, List<String>> _lithology = {
    "沉积岩": [
      "砾岩类",
      "砂岩类",
      "粉砂岩类",
      "页岩类",
      "泥岩（粘土岩）类",
      "非蒸发岩类",
      "蒸发岩类",
      "可燃有机岩",
      "松散堆积物",
    ],
    "火成岩": [
      "超基性岩类侵入岩",
      "基性岩类侵入岩",
      "中性岩类侵入岩",
      "酸性岩类侵入岩",
      "碱性岩类侵入岩",
      "煌斑岩类侵入岩",
      "碳酸岩类侵入岩",
      "脉岩",
      "超基性熔岩类",
      "基性熔岩类",
      "中性熔岩类",
      "酸性熔岩类",
      "碱性熔岩类",
      "流纹质火山岩（火山碎屑岩）类",
      "英安质火山岩（火山碎屑岩）类",
      "粗面质火山岩（火山碎屑岩）类",
      "安山质火山岩（火山碎屑岩）类",
      "玄武质火山岩（火山碎屑岩）类",
      "安粗质火山岩（火山碎屑岩）类",
      "玄武安山质火山岩（火山碎屑岩）类",
      "粗面玄武质火山岩（火山碎屑岩）类",
      "响岩质火山岩（火山碎屑岩）类",
      "超镁铁质火山岩（火山碎屑岩）类",
    ],
    "变质岩": [
      "板岩类",
      "千枚岩类",
      "片岩类",
      "片麻岩类",
      "麻粒岩类",
      "浅粒岩-变粒岩类",
      "斜长角闪岩类",
      "大理岩类",
      "榴辉岩类",
      "角岩类",
      "矽卡岩类",
      "构造岩",
      "糜棱岩",
      "混合岩",
      "其他变质岩类",
    ],
  };

  // 模块3的内部标签页控制器
  int _module3CurrentTab = 0;

  // 注意：修改为你真实的后端 IP 或域名
  final String _baseUrl = ApiConfig.baseUrl;

  // ======== 修复起点 1：新增万能照片提取小工具 ========
  List<Map<String, String>> _safeParsePhotos(dynamic rawList) {
    if (rawList == null || rawList is! List) return <Map<String, String>>[];
    List<Map<String, String>> result = [];

    for (var item in rawList) {
      if (item is Map) {
        result.add({
          'id':
              item['id']?.toString() ??
              'IMG_${DateTime.now().microsecondsSinceEpoch}',
          'path': item['path']?.toString() ?? '',
        });
      } else if (item is String) {
        // ⭐ 关键修复：兼容后端发来的 ["/uploads/xxxx.jpg"] 纯字符串数组
        result.add({
          // 使用微秒防止生成ID重复
          'id': 'IMG_${DateTime.now().microsecondsSinceEpoch}',
          'path': item,
        });
      }
    }
    return result;
  }

  // ============== 新增：自动填表懒加载逻辑 ==============
  Future<void> _fetchAutoFillData() async {
    // tip 1. 甲方可能会增减的自动计算字段，统一在这里维护：
    List<String> autoFieldsReq = [
      "地理位置",
      "地面高程",
      "多年平均降水量",
      "图幅",
      "所属三级生态基础分区",
      "坡度",
      "坡向",
      "土壤类型",
      "地貌类型",
      "生态区编号",
      "所属流域",
      // 在这里任意添加后台支持的字段
    ];

    // ⭐ 修改点2：更新UI占位符列表(因为图幅会展平为图幅号和图幅名，不需要占位"图幅")
    List<String> uiPlaceholders = [
      "地理位置",
      "地面高程",
      "多年平均降水量",
      "图幅名",
      "图幅号",
      "所属三级生态基础分区",
      "坡度",
      "坡向",
      "土壤类型",
      "地貌类型",
      "所属流域",
    ];

    // 先把要拉取的字段全部初始化为 "计算中..."
    setState(() {
      for (var field in autoFieldsReq) {
        _formData[field] = "";
      }
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      var dio = Dio();
      var response = await dio.post(
        "$_baseUrl/user/auto-fill",
        data: {
          "task_id": widget.taskId, // ⭐ 传入真实的 taskId
          "path_id": widget.pathId, // 点位接口也需要关联某条线，可以传这个
          "point_type": widget.templateType,
          "longitude": widget.currentGps.longitude,
          "latitude": widget.currentGps.latitude,
          "fields": autoFieldsReq, // 传给后台
        },
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );

      if (response.statusCode == 200 && response.data['data'] != null) {
        Map<String, dynamic> resData = response.data['data'];

        setState(() {
          resData.forEach((key, value) {
            // ⭐ 修改点3：针对地理位置做省市县拼接特判
            if (key == "地理位置" && value is Map) {
              String province = value['省'] ?? "";
              String city = value['市'] ?? "";
              String county = value['县'] ?? "";
              _formData['地理位置'] = "$province$city$county";
            }
            // 普通的嵌套字典处理 (例如 "图幅" 展平赋值为 图幅号、图幅名)
            else if (value is Map) {
              value.forEach((subKey, subValue) {
                _formData[subKey] = _formatNumber(subValue);
              });
            }
            // 其他常规属性直接赋值 (如 地面高程, 生态区编号等)
            else {
              _formData[key] = _formatNumber(value);
            }
          });
        });
      }
    } catch (e) {
      debugPrint("自动填表获取失败: $e");
      // 可以选择静默失败或弹窗
      setState(() {
        // 获取失败的替换为空白，方便用户手填
        for (var field in autoFieldsReq) {
          if (_formData[field] == "计算中...") _formData[field] = "";
        }
      });
    }
  }

  // 小工具：确保如果是数值，自动保留2位小数
  String _formatNumber(dynamic value) {
    if (value is num) {
      return value.toDouble().toStringAsFixed(2);
    }
    return value?.toString() ?? "";
  }

  //tip ============== HTTP：打点上传逻辑 || 修改点 ==============
  Future<void> _submitForm() async {
    // 弹出加载圈
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // ==========================================
      // ⭐ 新增代码：获取主编号
      // 根据模板类型，精确提取对应的编号字段
      // ==========================================
      String mainCode = "";
      if (widget.templateType == '1') {
        mainCode = _formData['点号'] ?? "";
      } else if (widget.templateType == '2') {
        mainCode = _formData['剖面号'] ?? "";
      } else if (widget.templateType == '3') {
        mainCode = _formData['样地号'] ?? "";
      } else if (widget.templateType == '4' || widget.templateType == '5') {
        mainCode = _formData['样方号'] ?? "";
      }

      // 降级容错(极为重要)：如果上面由于某种原因没取到(比如没网没拿到或者用户删了)，
      // 我们用级联运算符 ?? 硬抓一次，确保绝对有值
      if (mainCode.isEmpty) {
        mainCode =
            _formData['剖面号'] ??
            _formData['点号'] ??
            _formData['样方号'] ??
            _formData['样地号'] ??
            "UNKNOWN_CODE_${DateTime.now().millisecondsSinceEpoch}";
      }

      // 1. 分离文本和照片数据
      Map<String, dynamic> textData = {};
      List<MapEntry<String, MultipartFile>> fileEntries = [];

      for (var key in _formData.keys) {
        var value = _formData[key];

        // if (value is List) {
        //   // A. 处理公共层级的普通照片栏
        //   if (key.startsWith('照片_') ||
        //       key.contains('相片') ||
        //       key.contains('照片')) {
        //     for (var photo in value) {
        //       if (photo is Map && photo.containsKey('path')) {
        //         fileEntries.add(
        //           MapEntry(
        //             key, // 外层键名直接传
        //             await MultipartFile.fromFile(
        //               photo['path']!,
        //               filename: "${photo['id']}.jpg",
        //             ),
        //           ),
        //         );
        //       }
        //     }
        //   }
        //   // B. 处理结构体内部的数据 (重点修复区域)
        //   else if (key.startsWith('dynamic_assets_')) {
        //     List<Map<String, dynamic>> cleanStructList = [];
        //
        //     for (int i = 0; i < value.length; i++) {
        //       var struct = value[i];
        //       Map<String, dynamic> cleanStruct = {};
        //
        //       if (struct is Map) {
        //         // ⭐ 修复关键：使用 for...in...entries 代替 forEach，确保 await 真正阻塞等待！
        //         for (var entry in struct.entries) {
        //           var sKey = entry.key;
        //           var sValue = entry.value;
        //
        //           // 识别结构体里带有“照片”字样的 List 层
        //           if (sValue is List &&
        //               (sKey.startsWith('照片_') || sKey.contains('照片'))) {
        //             // 这是子结构体里的照片，我们需要给它取一个混合键名防止前后端混淆
        //             // 格式：父级名_索引_子集名，例如："dynamic_assets_sample_0_0_照片_记录"
        //             String complexKey = "${key}_${i}_$sKey";
        //
        //             for (var photo in sValue) {
        //               if (photo is Map && photo.containsKey('path')) {
        //                 fileEntries.add(
        //                   MapEntry(
        //                     complexKey,
        //                     await MultipartFile.fromFile(
        //                       photo['path']!,
        //                       filename: "${photo['id']}.jpg",
        //                     ),
        //                   ),
        //                 );
        //               }
        //             }
        //           } else {
        //             // 普通文本塞回结构体
        //             cleanStruct[sKey] = sValue;
        //           }
        //         }
        //         cleanStructList.add(cleanStruct);
        //       }
        //     }
        //     textData[key] = cleanStructList; // 剔除了照片后干净的 JSON 阵列
        //   }
        // }
        // 识别到第一层是列表：分为纯照片库，和动态结构体库
        if (value is List) {
          if (key.startsWith('照片_') ||
              key.contains('相片') ||
              key.contains('照片')) {
            // A. 处理公共层级的普通照片栏
            List<Map<String, String>> retainedOldPhotos = []; // ⭐ 存放未删除的老照片

            for (var photo in value) {
              if (photo is Map && photo.containsKey('path')) {
                String p = photo['path']!;
                if (p.startsWith('/uploads') || p.startsWith('http')) {
                  // ⭐ 老照片：不读文件，直接把 JSON 记录留给后端
                  retainedOldPhotos.add(Map<String, String>.from(photo));
                } else {
                  // ⭐ 新拍摄的照片：加入 File 队列，等待 Multipart 上传
                  fileEntries.add(
                    MapEntry(
                      key,
                      await MultipartFile.fromFile(
                        p,
                        filename: "${photo['id']}.jpg",
                      ),
                    ),
                  );
                }
              }
            }
            // 把老照片的相对路径信息赛回 JSON，让后端知道哪些老图被保留了
            // 如果后端不需要的话把这行删掉并跟后端定好协议即可
            if (retainedOldPhotos.isNotEmpty) textData[key] = retainedOldPhotos;
          } else if (key.startsWith('dynamic_assets_')) {
            // B. 处理结构体内部的数据
            List<Map<String, dynamic>> cleanStructList = [];

            for (int i = 0; i < value.length; i++) {
              var struct = value[i];
              Map<String, dynamic> cleanStruct = {};

              if (struct is Map<String, dynamic>) {
                // ⭐ 极其重大的修复：抛开 forEach，改回 for-in 循环！
                // 这样这里的 await 才能真正的挂起阻塞等待文件流组装！
                for (var entry in struct.entries) {
                  String sKey = entry.key;
                  var sValue = entry.value;

                  if (sValue is List &&
                      (sKey.startsWith('照片_') || sKey.contains('相片'))) {
                    List<Map<String, String>> structOldPhotos =
                        []; // ⭐ 存放结构体里的老图
                    String complexKey = "${key}_${i}_$sKey";

                    for (var photo in sValue) {
                      String p = photo['path']!;
                      if (p.startsWith('/uploads') || p.startsWith('http')) {
                        structOldPhotos.add(
                          Map<String, String>.from(photo),
                        ); // 保留老图
                      } else {
                        // 发射新图进队列 (这里的 await 现在完美生效了)
                        fileEntries.add(
                          MapEntry(
                            complexKey,
                            await MultipartFile.fromFile(
                              p,
                              filename: "${photo['id']}.jpg",
                            ),
                          ),
                        );
                      }
                    }
                    if (structOldPhotos.isNotEmpty) {
                      cleanStruct[sKey] = structOldPhotos;
                    }
                  } else {
                    cleanStruct[sKey] = sValue; // 普通文本塞回结构体
                  }
                }
                cleanStructList.add(cleanStruct);
              }
            }
            textData[key] = cleanStructList;
          }
        } else {
          // 常规外层纯文本录入
          textData[key] = value;
        }
      }

      // 2. 将数据组装为后端需要的 FormData 形态
      var dio = Dio();
      Response response;
      FormData formData = FormData.fromMap({
        // 后端要求的三个基础参数
        "task_id": widget.taskId, // ⭐ 传入真实的 taskId
        // "path_id": widget.pathId, // (可选) 如果你上传点位接口也需要关联某条线，可以传这个
        "lon": widget.currentGps.longitude,
        "lat": widget.currentGps.latitude,
        "path_id": widget.pathId,
        "type": widget.templateType,
        "point_serial": mainCode,
        // 所有纯文本统一转化为一个大 JSON 字符串
        "properties": jsonEncode(textData),
      });
      FormData formData_update = FormData.fromMap({
        "properties": jsonEncode(textData),
      });

      // 补充剥离出来的照片池
      formData.files.addAll(fileEntries);
      formData_update.files.addAll(fileEntries); // <—— 就是忘了这一行！加上！

      // 区分是更新实体点还是新建实体点
      if (widget.editPointId != null) {
        // A. 编辑更新模式
        response = await dio.post(
          // 或者 dio.put
          "$_baseUrl/user/points/${widget.editPointId}/update",
          data: formData_update,
          options: Options(headers: {"Authorization": "Bearer $token"}),
        );
      } else {
        // B. 原来的新建上传模式
        response = await dio.post(
          "$_baseUrl/user/points/upload",
          data: formData,
          options: Options(headers: {"Authorization": "Bearer $token"}),
        );
      }

      // // 3. 一次性发射给后端
      // response = await dio.post(
      //   "$_baseUrl/user/points/upload",
      //   data: formData,
      //   options: Options(headers: {"Authorization": "Bearer $token"}),
      // );

      Navigator.pop(context); // 关闭加载圈

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 上传成功，带着数据返回上一页并提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调查点位提交成功！'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败，服务端返回：${response.statusCode}')),
        );
      }
    } on DioException catch (dioError) {
      // ⭐ 核心抓错逻辑：提取后端真正返回的 message
      Navigator.pop(context); // 关加载圈
      String errorMsg = "请求失败";

      if (dioError.response != null) {
        // 如果后端有返回具体 JSON 原因（比如 {"message": "task_id 不能为空"}）
        final errorData = dioError.response?.data;
        errorMsg =
            "HTTP ${dioError.response?.statusCode}: ${errorData.toString()}";
      } else {
        errorMsg = dioError.message ?? "网络连接异常";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提交被拒绝:\n$errorMsg'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5), // 显示久一点方便你看
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('未知错误: $e')));
    }
  }

  //TIP ============== HTTP：获取递增编号 next_code ==============
  Future<void> _fetchNextCode() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');
      String? username = prefs.getString('username');
      var dio = Dio();

      var response = await dio.get(
        "$_baseUrl/user/points/next-number",
        queryParameters: {
          "task_id": widget.taskId,
          "path_id": widget.pathId,
          "type": widget.templateType,
        },
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );

      if (response.statusCode == 200 &&
          response.data['data']['next_code'] != null) {
        String nextCode = response.data['data']['next_code'].toString();

        setState(() {
          // ==========================================
          // ⭐ 小鱼，在这里写你自己分模板拼接的逻辑！
          // ==========================================
          _formData['调查人'] = username;
          _formData['记录人'] = username;
          // ⭐ 修改点：动态提取自动填表中拉回来的生态区编号，若缺失则提供默认占位防报错
          String ecoCode = _formData['生态区编号']?.toString() ?? "未知生态区";

          if (widget.templateType == '1') {
            _formData['点号'] = "$ecoCode-${widget.pathId}-D$nextCode";
          } else if (widget.templateType == '2') {
            _formData['剖面号'] = "$ecoCode-${widget.pathId}-P$nextCode";
          } else if (widget.templateType == '3') {
            _formData['样地号'] = "$ecoCode-${widget.pathId}-YD$nextCode";
          } else {
            _formData['样方号'] = "$ecoCode-${widget.pathId}-YF$nextCode";
          }
          // ==========================================
        });
      }
    } catch (e) {
      debugPrint("获取编号失败: $e");
      // 失败的话给个默认提示，允许手改
    }
  }

  // ⭐ 新增：处理新建打点的网络请求链
  Future<void> _loadNewPointDataSequence() async {
    // 1. 先等待自动填充接口返回（拿到生态区编号与各文本填充）
    await _fetchAutoFillData();
    // 2. 再根据拿到的生态区编号去拼接取号器的数据
    await _fetchNextCode();
  }

  @override
  void initState() {
    super.initState();
    // // 触发独立自增编号拉取
    // _fetchNextCode();
    // _initAutoFields();
    // //开启异步懒加载后台经纬度相交计算数据
    // _fetchAutoFillData();
    // ⭐ 新增逻辑：如果是编辑模式，将后端的大 JSON 覆盖合并进本页的 _formData
    if (widget.initialData != null) {
      // _formData.addAll(widget.initialData!);
      _parseAndMergeInitialData(widget.initialData!);
    } else {
      // 如果是新建模式才需要去拉取 next_code 和 auto_fill
      // (编辑模式下老数据已经有了，不需要重新去后端算默认值)
      // _initAutoFields();
      // _fetchAutoFillData();
      // _fetchNextCode();
      _initAutoFields();
      // ⭐ 修改点：使用异步任务流控制请求顺序，保障能够取到生态区编号
      _loadNewPointDataSequence();
    }
  }

  // ======== 修改起点 1：新增安全解析旧数据方法 ========
  // void _parseAndMergeInitialData(Map<String, dynamic> initialData) {
  //   initialData.forEach((key, value) {
  //     // 1. 如果后端传了 null（或者某字段遗漏），直接跳过！
  //     // 这样就能保留我们 _initAutoFields 里初始化的默认空数组，绝不会崩溃。
  //     if (value == null) return;
  //
  //     // 2. 处理动态结构体数组 (例如 dynamic_assets_ecoProblem, sample_0 等)
  //     if (key.startsWith('dynamic_assets_') && value is List) {
  //       List<Map<String, dynamic>> typedStructList = [];
  //       for (var item in value) {
  //         if (item is Map) {
  //           Map<String, dynamic> structMap = Map<String, dynamic>.from(item);
  //
  //           // ⚠️ 极度细节：结构体内部如果还有照片列表，也要将其强转为 String 泛型！
  //           structMap.forEach((sKey, sValue) {
  //             if ((sKey.startsWith('照片_') || sKey.contains('相片')) &&
  //                 sValue is List) {
  //               // List<Map<String, String>> photoList = [];
  //               // for (var p in sValue) {
  //               //   if (p is Map) photoList.add(Map<String, String>.from(p));
  //               // }
  //               // structMap[sKey] = photoList;
  //               structMap[sKey] = _safeParsePhotos(sValue);
  //             }
  //           });
  //
  //           typedStructList.add(structMap);
  //         }
  //       }
  //       _formData[key] = typedStructList;
  //     }
  //     // 3. 处理公共区的纯照片数组
  //     else if ((key.startsWith('照片_') || key.contains('相片')) && value is List) {
  //       // List<Map<String, String>> photoList = [];
  //       // for (var p in value) {
  //       //   if (p is Map) photoList.add(Map<String, String>.from(p));
  //       // }
  //       // _formData[key] = photoList;
  //       _formData[key] = _safeParsePhotos(value);
  //     }
  //     // 4. 其他文本、数值等常规简单字段，安全直接赋值
  //     else {
  //       _formData[key] = value;
  //     }
  //   });
  // }

  // ======== 修改终点 1 ========

  // ======== 修复起止点 1：安全合并回显数据 ========
  void _parseAndMergeInitialData(Map<String, dynamic> initialData) {
    // 1. 初步遍历赋值
    initialData.forEach((key, value) {
      if (value == null) return;

      // ⭐ 核心修复：精准隔离！
      // 必须保证名字里千万不能带有 "_照片_" 或者 "_相片_" 才代表它是【结构体本身】
      if (key.startsWith('dynamic_assets_') &&
          !key.contains('_照片_') &&
          !key.contains('_相片_') &&
          value is List) {
        List<Map<String, dynamic>> typedStructList = [];
        for (var item in value) {
          if (item is Map) {
            Map<String, dynamic> structMap = Map<String, dynamic>.from(item);
            // 这里是为了防备：如果有一天后端嵌套回传了，也能接住
            structMap.forEach((sKey, sValue) {
              if ((sKey.startsWith('照片_') || sKey.contains('相片')) &&
                  sValue is List) {
                structMap[sKey] = _safeParsePhotos(sValue);
              }
            });
            typedStructList.add(structMap);
          }
        }
        _formData[key] = typedStructList;
      }
      // 公共区的纯照片数组
      else if ((key.startsWith('照片_') || key.contains('相片')) && value is List) {
        _formData[key] = _safeParsePhotos(value);
      } else {
        // ⭐ 其他常规文本，以及形如 "dynamic_assets_sample..._照片" 的扁平外露图串
        // 不做解析原封不动塞进去，留给第二步！
        _formData[key] = value;
      }
    });

    // 2. ⭐ 将第一步保留下的扁平化样品图串数据塞回对应的深层节点内
    List<String> keysToRemove = [];
    _formData.forEach((key, value) {
      RegExp regex = RegExp(r"^(dynamic_assets_.+)_(\d+)_((?:照片|相片).*)$");
      var match = regex.firstMatch(key);

      if (match != null && value is List) {
        String structKey = match.group(1)!; // e.g. dynamic_assets_sample_0
        int index = int.parse(match.group(2)!); // 0
        String subKey = match.group(3)!; // 照片_记录

        if (_formData[structKey] is List &&
            (_formData[structKey] as List).length > index) {
          var structItem = _formData[structKey][index];
          if (structItem is Map) {
            // ⭐ 此时 value 是安然无恙的 ["/uploads/xxxx.jpg"] 列表，完美解析！
            structItem[subKey] = _safeParsePhotos(value);
          }
        }
        keysToRemove.add(key);
      }
    });

    // 清理废弃的平铺外层Key
    for (var k in keysToRemove) {
      _formData.remove(k);
    }
  }

  // ============== 核心逻辑：集中初始化所有“自动”字段 ==============
  void _initAutoFields() {
    String today =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    double currentLon = widget.currentGps.longitude;
    double currentLat = widget.currentGps.latitude;

    // 1. 定义源坐标系 (WGS84 GPS原始坐标)
    var projWGS84 = Projection.get('EPSG:4326')!;

    // 2. 注册并定义目标坐标系：CGCS2000 3度带 (举例：中央经线120度，EPSG代码为4528)
    // 小鱼注意：不同省份的中央经线不同！如果是全国通用的项目，可能需要根据当前经度动态计算 EPSG 编号。
    // 这里填入的字符串是标准的 proj4 通用定义，可以在 epsg.io 上查到。
    String cgcs2000Proj4Def =
        "+proj=tmerc +lat_0=0 +lon_0=120 +k=1 +x_0=39500000 +y_0=0 +ellps=GRS80 +units=m +no_defs";
    var projCGCS2000 = Projection.add('EPSG:4528', cgcs2000Proj4Def);

    // 3. 执行转换
    var pointWGS = Point(x: currentLon, y: currentLat);
    var pointPlanar = projWGS84.transform(projCGCS2000, pointWGS);

    // 4. 拼装字符串
    String planarString =
        'X: ${pointPlanar.x.toStringAsFixed(3)} m,  Y: ${pointPlanar.y.toStringAsFixed(3)} m';

    // 1. 三套模板都要用到的【公共基础字段】
    _formData.addAll({
      '表格模板编号': '${widget.templateType}',
      // // 模块0
      // '剖面特征描述': '无',
      // // 模块1
      // '图幅名': '北京市',
      // '图幅号': 'J50E001010',
      // '所属三级生态基础分区': '海河北系平原城镇和农田生态区',
      '日期': today,
      '路线号': '${widget.pathId}',
      '经度/纬度':
          'E:${widget.currentGps.longitude.toStringAsFixed(8)} / N:${widget.currentGps.latitude.toStringAsFixed(8)}',
      // '地面高程': '58 m',
      '平面坐标': planarString,
      // '地理位置': '北京市海淀区',
      // // 模块2
      // '地貌类型': '低海拔平原',
      // '坡度': '1°',
      // '所属流域': '海河区-潮白、北运、蓟运河水系-北四河下游平原',
      // '土地利用类型': '人工牧草地',
      // '生态系统类型': '人工（栽培）草地',
      // '多年平均降水量': '540.9 mm',
      // // 模块3A/B
      // '植被类型': '栽培植被',
      // '土壤类型': '铁铝土-湿热铁铝土-砖红壤',
      // '侵蚀类型': '水力侵蚀',
      // '侵蚀强度': '微度',
      // 模块4Projection.get('EPSG:4549')!
      '柱状剖面描述':
          '植被：描述植被类型、林草覆盖度、优势植物种，植被根系发育深度等；\n土壤：描述土体构型特征、土壤层颜色、厚度、质地、结构、砾石含量、含水率、pH值、根系深度、根系分布特征，表层土壤侵蚀程度，与下覆成土母质接触关系；\n成土母质：描述成土母质类型、厚度、结构、垂向变化、根系分布特征及与下覆基岩的接触关系等；\n成土母岩：描述岩性、主要岩石颜色、结构、构造、主要矿物、层理/节理产状、抗风化能力等；\n包气带：描述厚度、结构、含水性、渗透系数及分布特征等；\n风化壳：描述类型、厚度、风化程度、物质组成、垂直结构、分布特征等；\n总结描述成土岩石-成土母质-土壤-植被间关系、影响等。',
      '景观描述内容':
          '剖面点所处区域生态景观及突出的生态特征、生态问题的照片。描述内容：\n1、区域自然条件：描述该地理位置、气候区等整体特征；\n2、植被：植被类型、垂直结构及覆盖度等；\n3、生态系统及土地利用类型：描述生态系统类型、分布，土地利用类型、分布等；\n4、生态问题：生态问题类型、程度、分布、人类活动扰动、保护修复措施。',
      // 模块5
      '审核人': '',

      // 照片数据列表初始化
      '照片_柱状剖面图': <Map<String, String>>[],
      '照片_空间位置截图': widget.autoScreenshotPath != null
          ? <Map<String, String>>[
              {
                'id': "IMG_${DateTime.now().millisecondsSinceEpoch}",
                'path': widget.autoScreenshotPath!,
              },
            ]
          : <Map<String, String>>[], // 未传入则留空,
      '照片_样品照片': <Map<String, String>>[],
      '照片_景观描述照片': <Map<String, String>>[],
      '照片_林草样方照片': <Map<String, String>>[],
      'dynamic_assets_ecoProblem': <Map<String, dynamic>>[],
      'dynamic_assets_sample_0': <Map<String, dynamic>>[], // A.植被的样品
      'dynamic_assets_sample_1': <Map<String, dynamic>>[], // B.土壤的样品
      'dynamic_assets_sample_2': <Map<String, dynamic>>[], // C.成土母质的样品
      'dynamic_assets_sample_3': <Map<String, dynamic>>[], // D.包气带的样品
      'dynamic_assets_sample_4': <Map<String, dynamic>>[], // E.风化壳的样品
      'dynamic_assets_sample_5': <Map<String, dynamic>>[], // F.成土母岩的样品
      'dynamic_assets_sample_6': <Map<String, dynamic>>[], // F.水的样品
    });
    // 2. 根据不同模板，初始化其【专属独有字段】和【动态表单列表】
    if (widget.templateType == '1') {
      // ---- 调查点记录表 专属初始化 ----
      _formData.addAll({
        // 初始化调查点独有的照片或组
      });
    } else if (widget.templateType == '2') {
      // ---- 生态地质垂直剖面测量记录表 专属初始化 (保留你原来写好的) ----
    } else if (widget.templateType == '3') {
      // ---- 林草调查表 专属初始化 ----
    } else if (widget.templateType == '4') {
      // ---- 林草调查表 专属初始化 ----
    } else if (widget.templateType == '5') {
      // ---- 林草调查表 专属初始化 ----
    }
  }

  // ============== 通用 UI 构建器方法 ==============

  // 注意这里的 targetMap 参数！这就是巧妙之处：如果不传，就默认改 _formData；
  // 如果传了动态结构体字典，就改那个结构体的数据！
  Map<String, dynamic> get _defaultMap => _formData;

  // 1. 构建类型 自动 字段的显示框
  Widget _buildAutoBox(String label, {Map<String, dynamic>? targetMap}) {
    final map = targetMap ?? _defaultMap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        key: ValueKey("${map.hashCode}_auto_${label}_${map[label]}"),
        // ⭐ 新增：这把钥匙用字典的内存地址+标签名组成，绝对唯一！
        minLines: 1,
        // 关键1：最小1行
        maxLines: null,
        // 关键2：最大行数无限制，文本越多框越长
        keyboardType: TextInputType.multiline,
        // 关键3：允许多行输入
        initialValue: map[label] ?? '',
        readOnly: false,
        // 只读
        style: TextStyle(color: Colors.grey[1000], fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.bold,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // 2. 构建用户填写框
  Widget _buildInput(String label, {Map<String, dynamic>? targetMap}) {
    final map = targetMap ?? _defaultMap;
    String currentVal = (map[label] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextFormField(
        key: ValueKey("${map.hashCode}_input_$label"),
        // 这把钥匙用字典的内存地址+标签名组成，绝对唯一！
        // tip 必须加上这行！下次销毁重建时，它会从大字典里读取刚才写的值！
        initialValue: currentVal,
        onChanged: (val) => map[label] = val,
        minLines: 1,
        // 关键1：最小1行
        maxLines: null,
        // 关键2：最大行数无限制，文本越多框越长
        keyboardType: TextInputType.multiline,
        // 关键3：允许多行输入
        style: TextStyle(color: Colors.grey[1000], fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.bold,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // 3. 构建下拉选择框
  Widget _buildDropdown(
    String label,
    List<String> items, {
    Map<String, dynamic>? targetMap,
  }) {
    final map = targetMap ?? _defaultMap;
    // ⭐ 新增：安全读取当前值，如果当前值不在 items 列表里，强制设为 null
    String? currentVal = map[label] != null ? map[label].toString() : null;
    if (currentVal != null && !items.contains(currentVal)) {
      currentVal = null;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: DropdownButtonFormField<String>(
        key: ValueKey("${map.hashCode}_drop_$label"),
        // ⭐ 修改位置 1：增加 isExpanded 属性
        // 作用：强制下拉框内容填充可用空间，而不是由内容撑开宽度
        // ⭐ 极其重要：绑定当前值，重建时才不会变成白板
        initialValue: currentVal,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.bold,
            // 此处的 overflow 对标签起作用
            overflow: TextOverflow.ellipsis,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          // 禁用时变灰
          isDense: true,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
        ),

        // ⭐ 修改位置 2：对 DropdownMenuItem 的 child 进行包裹
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e,
                  // 作用：防止下拉列表中的长文本再次触发溢出
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            )
            .toList(),

        onChanged: (val) {
          setState(() => map[label] = val);
        },

        // ⭐ 修改位置 3：增加 selectedItemBuilder (可选但推荐)
        // 作用：控制“已选中”状态在输入框里的显示样式，确保它也不会溢出
        selectedItemBuilder: (BuildContext context) {
          return items.map<Widget>((String item) {
            return Text(
              item,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            );
          }).toList();
        },
      ),
    );
  }

  // ⭐ 修改位置：新增二级联动组件函数
  Widget _buildLinkedDropdown(
    String label,
    Map<String, List<String>> dataMap, {
    Map<String, dynamic>? targetMap,
  }) {
    final map = targetMap ?? _defaultMap;
    // 存储格式建议为 "大类-具体值"，或者只存具体值
    String? currentVal = map[label]?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        // 使用 InkWell 模拟下拉框点击外观
        onTap: () => _showLevelOnePicker(label, dataMap, map),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
              color: Colors.green[800],
              fontWeight: FontWeight.bold,
              overflow: TextOverflow.ellipsis,
            ),
            filled: true,
            fillColor: Colors.grey[200],
            isDense: true,
            suffixIcon: Icon(Icons.arrow_drop_down),
            // 模拟下拉箭头
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            currentVal ?? "请选择",
            style: TextStyle(
              fontSize: 14,
              color: currentVal == null ? Colors.grey : Colors.black,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ⭐ 逻辑实现：第一级选择（大类）
  void _showLevelOnePicker(
    String label,
    Map<String, List<String>> dataMap,
    Map map,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: dataMap.keys
            .map(
              (category) => ListTile(
                title: Text(category),
                onTap: () {
                  Navigator.pop(context);
                  // 选中大类后，立即进入第二级选择
                  _showLevelTwoPicker(label, category, dataMap[category]!, map);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  // ⭐ 逻辑实现：第二级选择（具体值）
  void _showLevelTwoPicker(
    String label,
    String category,
    List<String> subItems,
    Map map,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text("选择$category的具体类型", style: TextStyle(fontSize: 16)),
            automaticallyImplyLeading: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: subItems
                  .map(
                    (item) => ListTile(
                      title: Text(item),
                      onTap: () {
                        setState(() {
                          // 存储最终结果，例如 "植被: 乔木"
                          // map[label] = "$category: $item";
                          map[label] = item;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // 4. 构建拍照横向列表框（支持多图）
  Widget _buildPhotoField(
    String title,
    String mapKey, {
    Map<String, dynamic>? targetMap,
  }) {
    final map = targetMap ?? _defaultMap;
    // 为了容错，如果这个键尚未初始化，先初始化它
    if (map[mapKey] == null) {
      map[mapKey] = <Map<String, String>>[];
    }
    List<Map<String, String>> photos = map[mapKey] as List<Map<String, String>>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        Container(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // 拍照按钮
              // ================= 修改起点：拍照/相册选项按钮 =================
              GestureDetector(
                onTap: () {
                  // 点击弹出底部选择抽屉
                  showModalBottomSheet(
                    context: context,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (BuildContext bc) {
                      return SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.camera_alt,
                                color: Colors.green,
                              ),
                              title: Text('拍照'),
                              onTap: () async {
                                Navigator.of(context).pop(); // 先关闭抽屉
                                final picker = ImagePicker();
                                final XFile? img = await picker.pickImage(
                                  source: ImageSource.camera,
                                );
                                if (img != null) {
                                  // ⭐ 引入微秒 microseconds 防同秒冲突
                                  DateTime now = DateTime.now();
                                  String timeStr =
                                      "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.microsecond}";

                                  setState(() {
                                    photos.add({
                                      'id': "IMG_$timeStr",
                                      'path': img.path,
                                    });
                                  });
                                }
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.photo_library,
                                color: Colors.blueAccent,
                              ),
                              title: Text('从相册选择 (支持多选)'),
                              onTap: () async {
                                Navigator.of(context).pop(); // 先关闭抽屉
                                final picker = ImagePicker();
                                // ⭐ 使用 pickMultiImage 支持用户在相册里一次选多张图！
                                final List<XFile>? images = await picker
                                    .pickMultiImage();
                                if (images != null && images.isNotEmpty) {
                                  setState(() {
                                    for (var img in images) {
                                      // 每张图单独抓取瞬间时间(微秒)作为唯一ID
                                      DateTime now = DateTime.now();
                                      String timeStr =
                                          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}_${now.microsecond}";

                                      photos.add({
                                        'id': "IMG_$timeStr",
                                        'path': img.path,
                                      });
                                    }
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: DottedBorder(
                  color: Colors.grey,
                  strokeWidth: 2,
                  dashPattern: [6, 4],
                  child: Container(
                    width: 80,
                    height: 80,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, color: Colors.grey, size: 28),
                        SizedBox(height: 4),
                        Text(
                          "添加",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ================= 修改终点 =================
              SizedBox(width: 10),
              // 照片陈列
              ...photos.asMap().entries.map((e) {
                final photoData = e.value;
                String rawPath = photoData['path']!;
                // ⭐ 核心逻辑 1：判断是否是网络图片(以 /uploads 或 http 开头)
                bool isNetwork =
                    rawPath.startsWith('/uploads') ||
                    rawPath.startsWith('http');

                // ⭐ 核心逻辑 2：动态拼接用于展示的绝对 URL
                String displayUrl = rawPath.startsWith('/uploads')
                    ? "${ApiConfig.photoUrl}$rawPath" // 拼接你的全局域名
                    : rawPath;
                return Stack(
                  children: [
                    // 点击缩略图放大查看
                    GestureDetector(
                      onTap: () {
                        // 推送一个全屏的图片查看器
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(photoData['id']!),
                                backgroundColor: Colors.white,
                              ),
                              backgroundColor: Colors.white,
                              body: Center(
                                child: InteractiveViewer(
                                  // 支持双指缩放、拖拽
                                  // child: Image.file(File(photoData['path']!)),
                                  // ⭐ 放大查看器也要兼容网络图片和本地图片
                                  child: isNetwork
                                      ? Image.network(displayUrl) // 网络图
                                      : Image.file(File(rawPath)), // 本地新拍图
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: EdgeInsets.only(right: 10),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white),
                          image: DecorationImage(
                            image: isNetwork
                                ? NetworkImage(displayUrl) as ImageProvider
                                : FileImage(File(rawPath)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    // 底部覆盖层展示生成的编号
                    Positioned(
                      bottom: 4,
                      left: 0,
                      child: Container(
                        width: 80,
                        color: Colors.black54,
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          photoData['id']!.substring(4), // 显示时间戳部分
                          style: TextStyle(color: Colors.white, fontSize: 9),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 删除按钮小红叉，放在右上角
                    Positioned(
                      right: 0,
                      top: -10,
                      child: IconButton(
                        icon: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: () => setState(() => photos.removeAt(e.key)),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  // 5. 态追加自定义结构体组
  Widget _buildDynamicCustomGroup_ecoProblem() {
    // ⭐ 新增保护性回退：如果在极其极端的情况下这玩意儿变成 null 了，兜底塞个空数组给它
    if (_formData['dynamic_assets_ecoProblem'] == null) {
      _formData['dynamic_assets_ecoProblem'] = <Map<String, dynamic>>[];
    }
    List<Map<String, dynamic>> dynamicAssets =
        _formData['dynamic_assets_ecoProblem'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 渲染已添加的各个自定义模块
        ...dynamicAssets.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> itemMap = entry.value;

          return Card(
            color: Colors.orange[50], // 给定一个醒目的外框背景
            margin: EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "生态问题 #${index + 1}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            setState(() => dynamicAssets.removeAt(index)),
                      ),
                    ],
                  ),
                  // todo 在这里，我们就组装你需要的结构体了！将 itemMap 传入 targetMap
                  _buildLinkedDropdown(
                    '生态问题类型',
                    _ecoProblem,
                    targetMap: itemMap,
                  ),
                  _buildDropdown('生态问题程度', [
                    '无',
                    '未',
                    '潜在',
                    '微度',
                    '轻度',
                    '中度',
                    '强度',
                    '重度',
                    '极重度',
                    '极强度',
                    '剧烈',
                  ], targetMap: itemMap),
                  _buildDropdown('生态问题影响因素', [
                    '人为',
                    '天然',
                    '人为和天然',
                  ], targetMap: itemMap),
                  _buildInput('修复措施', targetMap: itemMap),
                ],
              ),
            ),
          );
        }).toList(),

        // “新建某某某” 按钮（做得和Input输入框一样长）
        InkWell(
          onTap: () {
            setState(() {
              // 每当点击，就往动态列表里塞一个空字典和特有的照片List。
              // 上面的 .map 就会渲染出多一个卡片！
              dynamicAssets.add(<String, dynamic>{
                '时间记录': DateTime.now().toString().substring(0, 16),
                '照片_记录': <Map<String, String>>[],
              });
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(
                color: Colors.grey[400]!,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.green[800]),
                SizedBox(width: 8),
                Text(
                  "新建生态问题",
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicCustomGroup_sample(String listKey) {
    // 增加一个防御性初始化（如果没找到，就给它一个空数组防报错）
    if (_formData[listKey] == null) {
      _formData[listKey] = <Map<String, dynamic>>[];
    }

    // 这里不再写死，而是根据传入的 listKey 去拿数据
    List<Map<String, dynamic>> dynamicAssets = _formData[listKey];

    // 1. 智能推断前缀和标题 (根据你传入的 dynamic_assets_sample_X 下标区分)
    String categoryCode = 'X';
    String title = '未知样品';

    // 按照你之前的 7 个 tab 下标推断归属：
    if (listKey.endsWith('_0')) {
      categoryCode = 'B';
      title = '植被样品';
    } else if (listKey.endsWith('_1')) {
      categoryCode = 'T';
      title = '土壤样品';
    } else if (listKey.endsWith('_2')) {
      categoryCode = 'Z';
      title = '成土母质样品';
    } else if (listKey.endsWith('_3')) {
      categoryCode = 'Q';
      title = '包气带样品';
    } // 注：包气带甲方若没定字母，先用Q代替
    else if (listKey.endsWith('_4')) {
      categoryCode = 'F';
      title = '风化壳样品';
    } else if (listKey.endsWith('_5')) {
      categoryCode = 'Y';
      title = '成土母岩样品';
    } else if (listKey.endsWith('_6')) {
      categoryCode = 'S';
      title = '水样品';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 渲染已添加的各个自定义模块
        ...dynamicAssets.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> itemMap = entry.value;

          return Card(
            color: Colors.blue[50], // 给定一个醒目的外框背景
            margin: EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "$title #${index + 1}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            setState(() => dynamicAssets.removeAt(index)),
                      ),
                    ],
                  ),
                  // todo 在这里，我们就组装你需要的结构体了！将 itemMap 传入 targetMap
                  _buildInput('采样深度(cm)', targetMap: itemMap),
                  _buildInput('样品编号', targetMap: itemMap),
                  _buildPhotoField('样品照片', '照片_记录', targetMap: itemMap),
                ],
              ),
            ),
          );
        }).toList(),

        // “新建某某某” 按钮（做得和Input输入框一样长）
        InkWell(
          onTap: () {
            setState(() {
              // 每当点击，就往动态列表里塞一个空字典和特有的照片List。
              // 上面的 .map 就会渲染出多一个卡片！
              // ⭐ 核心算法：提取当前用户表单中的主编号
              // 小鱼，这里按照优先级，获取 剖面号 > 点号 > 样地号
              // 如果都还没取到（比如刚进页面请求还没回来），就默认前缀为 "TEMP"
              String baseNumber =
                  _formData['剖面号'] ??
                  _formData['点号']
                  // ?? _formData['样方号']
                  // ?? _formData['样地号']
                  ??
                  "TEMP";

              // 发射编号：当前分类中有多少个数据，就加1，并补齐为 3位 (例如 001)
              int nextIndex = dynamicAssets.length + 1;
              String seqStr = nextIndex.toString().padLeft(3, '0');

              // 终极拼接：主号 + 模块定名字母 + 序号。 例如：R1-P001-T001
              String finalSampleCode = "$baseNumber-$categoryCode$seqStr";

              dynamicAssets.add(<String, dynamic>{
                '样品编号': finalSampleCode,
                '时间记录': DateTime.now().toString().substring(0, 16),
                '照片_记录': <Map<String, String>>[],
              });
            });
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border.all(
                color: Colors.grey[400]!,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Colors.green[800]),
                SizedBox(width: 8),
                Text(
                  "新建样品",
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ================= 模板渲染引擎 =================

  // ▶ 模板1：生态地质调查点记录表
  List<Widget> _buildTemplate1() {
    return [
      // ================= 模块 0: 总览图 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('拍照模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          _buildPhotoField('景观描述照片', '照片_景观描述照片'),
          _buildPhotoField('空间位置截图', '照片_空间位置截图'),
        ],
      ),

      // ================= 模块 1: 基础信息 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('基础信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          // 空行防止字段被遮挡
          Row(),
          _buildInput('工作区'),
          // _buildAutoBox('图幅名/图幅号'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('图幅名')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('图幅号')),
            ],
          ),
          _buildAutoBox('所属三级生态基础分区'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('日期')),
              SizedBox(width: 8),
              Expanded(
                child: _buildDropdown('天气', [
                  '晴朗',
                  '多云',
                  '阴天',
                  '小雨',
                  '大雨',
                  '雪',
                ]),
              ),
            ],
          ),
          // _buildAutoBox('路线号/点号/剖面号'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('路线号')),
              SizedBox(width: 8),
              Expanded(flex: 2, child: _buildAutoBox('点号')),
            ],
          ),
          _buildAutoBox('经度/纬度'),
          _buildAutoBox('平面坐标'),
          Row(
            children: [
              Expanded(flex: 2, child: _buildAutoBox('地理位置')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('地面高程')),
            ],
          ),
        ],
      ),

      // ================= 模块 2: 地貌与生态特征 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('地类信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Row(),
          Row(
            children: [
              Expanded(child: _buildAutoBox('地貌类型')),
              SizedBox(width: 8),
              Expanded(child: _buildLinkedDropdown('地貌部位', _geomorphic)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildAutoBox('坡度')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('坡向')),
            ],
          ),
          _buildAutoBox('所属流域'),
          Row(
            children: [
              Expanded(child: _buildLinkedDropdown('土地利用类型', _landUse)),
              SizedBox(width: 8),
              Expanded(child: _buildLinkedDropdown('生态系统类型', _ecosystem)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInput('地表蒸散量')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('地下水埋深')),
            ],
          ),
          _buildAutoBox('多年平均降水量'),
          _buildDynamicCustomGroup_ecoProblem(),
        ],
      ),

      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 保证收起折叠面板时内部数据死死保留不销毁！
        title: Text('特征模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          // 横向分段控件选择 (共 7 个标签)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: List<Widget>.generate(7, (int index) {
              final labels = ['植被', '土壤', '成土母质', '包气带', '风化壳', '成土母岩', '水'];
              return ChoiceChip(
                label: Text(labels[index]),
                selected: _module3CurrentTab == index,
                onSelected: (bool selected) {
                  setState(
                    () => _module3CurrentTab = selected
                        ? index
                        : _module3CurrentTab,
                  );
                },
              );
            }).toList(),
          ),
          SizedBox(height: 10),

          // ⭐ 核心修复区域：IndexedStack 的 children 数组必须雷打不动地包含 7 个 Column
          IndexedStack(
            index: _module3CurrentTab, // 绑定当前应该显示第几个
            children: [
              // ----------------- [下标 0] 标签面板 A: 植被特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 3, child: _buildAutoBox('植被类型')),
                      SizedBox(width: 8),
                      Expanded(flex: 3, child: _buildInput('植被覆盖度(%)')),
                    ],
                  ),
                  _buildInput('植被高度(m)'),
                  _buildDropdown('起源', ['自然植被', '人工植被']),
                  Row(
                    children: [
                      Expanded(child: _buildInput('植被优势种')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('乡土适生种')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('引进适生种')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_0"),
                ],
              ),

              // ----------------- [下标 1] 标签面板 B: 土壤特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildAutoBox('土壤类型')),
                      SizedBox(width: 8),
                      Expanded(child: _buildAutoBox('侵蚀类型')),
                      SizedBox(width: 8),
                      Expanded(child: _buildAutoBox('侵蚀强度')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('土壤颜色')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('厚度(cm)')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('土被覆盖率(%)')),
                    ],
                  ),
                  _buildInput('分层结构'),
                  _buildDropdown('土壤质地', ['粘土', '壤土', '砂壤土', '壤砂土', '砂土']),
                  Row(
                    children: [
                      Expanded(child: _buildInput('紧实度')),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown('结持性', [
                          '疏松',
                          '坚实',
                          '很坚实',
                          '极坚实',
                        ]),
                      ),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('砾石含量(%)')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('pH值')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('温度(℃)')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('含水量')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('电导率')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('含盐量')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_1"),
                ],
              ),

              // ----------------- [下标 2] 标签面板 C: 母质特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown('成土母质类型', [
                    '风积沙',
                    '原生黄土',
                    '黄土状物质 (次生黄土)',
                    '残积物',
                    '坡积物',
                    '冲积物',
                    '海岸沉积物',
                    '湖泊沉积物',
                    '河流沉积物',
                    '火成碎屑沉积物',
                    '冰川沉积物 (冰碛物)',
                    '冰水沉积物',
                    '有机沉积物',
                    '崩积物',
                    '(古) 红黏土',
                    '其他',
                  ]),
                  Row(
                    children: [
                      Expanded(child: _buildInput('成土母质颜色')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('成土母质厚度(m)')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('成土母质层结构')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('成土母质松散度')),
                    ],
                  ),
                  _buildInput('成土母质成分及比例'),
                  Divider(),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_2"),
                ],
              ),

              // ----------------- [下标 3] 标签面板 D: 包气带 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildInput('包气带厚度(m)')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('包气带渗透系数')),
                    ],
                  ),
                  _buildInput('包气带垂直结构'),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_3"),
                ],
              ),

              // ----------------- [下标 4] 标签面板 E: 风化壳 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildInput('风化壳类型')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('风化壳厚度(m)')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('风化壳风化程度')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('风化壳垂直结构')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_4"),
                ],
              ),

              // ----------------- [下标 5] 标签面板 F: 成土母岩 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLinkedDropdown("成土母岩岩性", _lithology),
                  _buildInput('成土母岩颜色'),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_5"),
                ],
              ),

              // ----------------- [下标 6] 标签面板 G: 水 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_6"),
                ],
              ),
            ],
          ),
        ],
      ),

      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('概述模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text('', style: TextStyle()),
          _buildAutoBox('柱状剖面描述'),
          _buildAutoBox('景观描述内容'),
        ],
      ),

      // ================= 模块 5: 责任声明 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('填表人员记录', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text('', style: TextStyle(color: Colors.grey)),
          Row(
            children: [
              Expanded(child: _buildAutoBox('调查人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('记录人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('审核人')),
            ],
          ),
        ],
      ),
      SizedBox(height: 50),
      // 底部留白
    ];
  }

  // ▶ 模板2：生态地质垂直剖面测量记录表 (把你写好的代码平移过来)
  List<Widget> _buildTemplate2() {
    return [
      // ================= 模块 0: 总览图 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('拍照模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          _buildPhotoField('柱状剖面图', '照片_柱状剖面图'),
          // _buildAutoBox('剖面特征描述'),
          _buildPhotoField('景观描述照片', '照片_景观描述照片'),
          _buildPhotoField('空间位置截图', '照片_空间位置截图'),
        ],
      ),

      // ================= 模块 1: 基础信息 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('基础信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          // 空行防止字段被遮挡
          Row(),
          _buildInput('工作区'),
          // _buildAutoBox('图幅名/图幅号'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('图幅名')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('图幅号')),
            ],
          ),
          _buildAutoBox('所属三级生态基础分区'),
          // _buildDropdown('剖面类型', ['自然剖面', '人工剖面', '浅钻']),
          // _buildDropdown('天气', ['晴朗', '多云', '阴天', '小雨', '大雨', '雪']),
          Row(
            children: [
              Expanded(child: _buildDropdown('剖面类型', ['自然剖面', '人工剖面', '浅钻'])),
              SizedBox(width: 8),
              Expanded(
                child: _buildDropdown('天气', [
                  '晴朗',
                  '多云',
                  '阴天',
                  '小雨',
                  '大雨',
                  '雪',
                ]),
              ),
            ],
          ),
          _buildAutoBox('日期'),
          // _buildAutoBox('路线号/点号/剖面号'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('路线号')),
              SizedBox(width: 8),
              Expanded(flex: 2, child: _buildAutoBox('剖面号')),
            ],
          ),
          _buildAutoBox('经度/纬度'),
          _buildAutoBox('平面坐标'),
          Row(
            children: [
              Expanded(flex: 2, child: _buildAutoBox('地理位置')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('地面高程')),
            ],
          ),
        ],
      ),

      // ================= 模块 2: 地貌与生态特征 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('地类信息模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Row(),
          Row(
            children: [
              Expanded(child: _buildAutoBox('地貌类型')),
              SizedBox(width: 8),
              Expanded(child: _buildLinkedDropdown('地貌部位', _geomorphic)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildAutoBox('坡度')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('所属流域')),
            ],
          ),
          // _buildAutoBox('土地利用/生态系统类型'),
          Row(
            children: [
              Expanded(child: _buildLinkedDropdown('土地利用类型', _landUse)),
              SizedBox(width: 8),
              Expanded(child: _buildLinkedDropdown('生态系统类型', _ecosystem)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInput('地表蒸散量')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('地下水埋深')),
            ],
          ),
          _buildAutoBox('多年平均降水量'),
          _buildDynamicCustomGroup_ecoProblem(),
        ],
      ),

      // ================= 模块 3: 详细特征观测 =================
      // ================= 模块 3: 详细特征观测 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 保证收起折叠面板时内部数据死死保留不销毁！
        title: Text('特征模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          // 横向分段控件选择 (共 7 个标签)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: List<Widget>.generate(7, (int index) {
              final labels = ['植被', '土壤', '成土母质', '包气带', '风化壳', '成土母岩', '水'];
              return ChoiceChip(
                label: Text(labels[index]),
                selected: _module3CurrentTab == index,
                onSelected: (bool selected) {
                  setState(
                    () => _module3CurrentTab = selected
                        ? index
                        : _module3CurrentTab,
                  );
                },
              );
            }).toList(),
          ),
          SizedBox(height: 10),

          // ⭐ 核心修复区域：IndexedStack 的 children 数组必须雷打不动地包含 7 个 Column
          IndexedStack(
            index: _module3CurrentTab, // 绑定当前应该显示第几个
            children: [
              // ----------------- [下标 0] 标签面板 A: 植被特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 3, child: _buildAutoBox('植被类型')),
                      SizedBox(width: 8),
                      Expanded(flex: 3, child: _buildInput('植被覆盖度(%)')),
                    ],
                  ),
                  _buildInput('植被高度(m)'),
                  _buildDropdown('起源', ['自然植被', '人工植被']),
                  Row(
                    children: [
                      Expanded(child: _buildInput('植被优势种')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('乡土适生种')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('引进适生种')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_0"),
                ],
              ),

              // ----------------- [下标 1] 标签面板 B: 土壤特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildAutoBox('土壤类型')),
                      SizedBox(width: 8),
                      Expanded(child: _buildAutoBox('侵蚀类型')),
                      SizedBox(width: 8),
                      Expanded(child: _buildAutoBox('侵蚀强度')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('土壤颜色')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('厚度(cm)')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('土被覆盖率(%)')),
                    ],
                  ),
                  _buildInput('分层结构'),
                  _buildDropdown('土壤质地', ['粘土', '壤土', '砂壤土', '壤砂土', '砂土']),
                  Row(
                    children: [
                      Expanded(child: _buildInput('紧实度')),
                      SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown('结持性', [
                          '疏松',
                          '坚实',
                          '很坚实',
                          '极坚实',
                        ]),
                      ),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('砾石含量(%)')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('pH值')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('温度(℃)')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('含水量')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('电导率')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('含盐量')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_1"),
                ],
              ),

              // ----------------- [下标 2] 标签面板 C: 母质特征 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown('成土母质类型', [
                    '风积沙',
                    '原生黄土',
                    '黄土状物质 (次生黄土)',
                    '残积物',
                    '坡积物',
                    '冲积物',
                    '海岸沉积物',
                    '湖泊沉积物',
                    '河流沉积物',
                    '火成碎屑沉积物',
                    '冰川沉积物 (冰碛物)',
                    '冰水沉积物',
                    '有机沉积物',
                    '崩积物',
                    '(古) 红黏土',
                    '其他',
                  ]),
                  Row(
                    children: [
                      Expanded(child: _buildInput('成土母质颜色')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('成土母质厚度(m)')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('成土母质层结构')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('成土母质松散度')),
                    ],
                  ),
                  _buildInput('成土母质成分及比例'),
                  Divider(),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_2"),
                ],
              ),

              // ----------------- [下标 3] 标签面板 D: 包气带 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildInput('包气带厚度(m)')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('包气带渗透系数')),
                    ],
                  ),
                  _buildInput('包气带垂直结构'),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_3"),
                ],
              ),

              // ----------------- [下标 4] 标签面板 E: 风化壳 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildInput('风化壳类型')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('风化壳厚度(m)')),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildInput('风化壳风化程度')),
                      SizedBox(width: 8),
                      Expanded(child: _buildInput('风化壳垂直结构')),
                    ],
                  ),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_4"),
                ],
              ),

              // ----------------- [下标 5] 标签面板 F: 成土母岩 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLinkedDropdown("成土母岩岩性", _lithology),
                  _buildInput('成土母岩颜色'),
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_5"),
                ],
              ),

              // ----------------- [下标 6] 标签面板 G: 水 -----------------
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDynamicCustomGroup_sample("dynamic_assets_sample_6"),
                ],
              ),
            ],
          ),
        ],
      ),

      // ================= 模块 4: 采样与影像资料 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('概述模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text('', style: TextStyle()),
          _buildAutoBox('柱状剖面描述'),
          _buildAutoBox('景观描述内容'),
        ],
      ),

      // ================= 模块 5: 责任声明 =================
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('填表人员记录', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text('', style: TextStyle(color: Colors.grey)),
          Row(
            children: [
              Expanded(child: _buildAutoBox('调查人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('记录人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('审核人')),
            ],
          ),
        ],
      ),
      SizedBox(height: 50), // 底部留白
    ];
  }

  // ▶ 模板3：林草调查表_乔木
  List<Widget> _buildTemplate3() {
    return [
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方取样模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [_buildPhotoField('林草样方照片', '照片_林草样方照片')],
      ),
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方记录模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text(''),
          Row(
            children: [
              Expanded(flex: 2, child: _buildAutoBox('样地号')),
              SizedBox(width: 8),
              Expanded(child: _buildDropdown('样地面积(㎡)', ['20*20', '30*30'])),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildDropdown('森林起源', ['天然林', '人工林', '次生林'])),
              SizedBox(width: 8),
              Expanded(
                child: _buildDropdown('植被类型', [
                  '栽培植被',
                  '针叶林',
                  '阔叶林',
                  '草甸',
                  '沼泽',
                  '灌丛',
                  '针阔叶混交林',
                  '草原',
                  '高山植被',
                  '无植被地段',
                  '荒漠',
                  '草丛',
                ]),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInput('植被总盖度(%)')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('林分郁闭度(%)')),
            ],
          ),
          _buildInput('优势种'),
          Row(
            children: [
              Expanded(child: _buildInput('平均年龄(n)')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('平均树高(m)')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('平均胸径(cm)')),
            ],
          ),
          _buildInput('根系发育深度'),
          _buildInput('林草样方总体描述'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('调查人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('记录人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('审核人')),
            ],
          ),
        ],
      ),
      SizedBox(height: 50),
    ];
  }

  // ▶ 模板4：林草调查表_灌木
  List<Widget> _buildTemplate4() {
    return [
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方取样模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [_buildPhotoField('林草样方照片', '照片_林草样方照片')],
      ),
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方记录模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text(''),
          Row(
            children: [
              Expanded(flex: 2, child: _buildAutoBox('样方号')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('灌木样方面积(㎡)')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInput('优势种')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('覆盖度(%)')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('平均高(m)')),
            ],
          ),
          _buildInput('根系发育深度'),
          _buildInput('林草样方总体描述'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('调查人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('记录人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('审核人')),
            ],
          ),
        ],
      ),

      SizedBox(height: 50),
    ];
  }

  // ▶ 模板5：林草调查表_草木
  List<Widget> _buildTemplate5() {
    return [
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方取样模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [_buildPhotoField('林草样方照片', '照片_林草样方照片')],
      ),
      ExpansionTile(
        initiallyExpanded: true,
        maintainState: true, // ⭐ 新增：保持状态，收起不销毁内存
        title: Text('样方记录模块', style: TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Text(''),
          Row(
            children: [
              Expanded(flex: 2, child: _buildAutoBox('样方号')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('草木样方面积(㎡)')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInput('优势种')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('覆盖度(%)')),
              SizedBox(width: 8),
              Expanded(child: _buildInput('平均高(m)')),
            ],
          ),
          _buildInput('根系发育深度'),
          _buildInput('林草样方总体描述'),
          Row(
            children: [
              Expanded(child: _buildAutoBox('调查人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('记录人')),
              SizedBox(width: 8),
              Expanded(child: _buildAutoBox('审核人')),
            ],
          ),
        ],
      ),

      SizedBox(height: 50),
    ];
  }

  // ============== 页面构建 ==============
  @override
  Widget build(BuildContext context) {
    // 通过 widget.templateType 判断使用什么标题，后续你可以使用 if-else 渲染整块不同的树
    String title = "测量记录表";
    if (widget.templateType == '1') title = "生态地质调查点记录表";
    if (widget.templateType == '2') title = "生态地质垂直剖面测量记录表";
    if (widget.templateType == '3') title = "乔木_生态地质垂直剖面测量点林草调查表";
    if (widget.templateType == '4') title = "灌木_生态地质垂直剖面测量点林草调查表";
    if (widget.templateType == '5') title = "草木_生态地质垂直剖面测量点林草调查表";

    // 动态分发 Body 块
    List<Widget> formChildren;
    if (widget.templateType == '1') {
      formChildren = _buildTemplate1();
    } else if (widget.templateType == '2') {
      formChildren = _buildTemplate2();
    } else if (widget.templateType == '3') {
      formChildren = _buildTemplate3();
    } else if (widget.templateType == '4') {
      formChildren = _buildTemplate4();
    } else {
      formChildren = _buildTemplate5();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: TextStyle(color: Colors.black, fontSize: 18),
        backgroundColor: Colors.green,
        actions: [
          TextButton(
            onPressed: () {
              // 进行表单校验后退出并返回 formData 给调用者
              _submitForm();
              // Navigator.pop(context, _formData);
            },
            child: Text(
              "完成提交",
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      // 外层使用 ListView 避免键盘遮挡报错
      body: ListView(padding: EdgeInsets.all(12), children: formChildren),
    );
  }
}
