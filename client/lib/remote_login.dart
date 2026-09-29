import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'data/fund_repository.dart';

class RemoteLoginPage extends StatefulWidget {
  const RemoteLoginPage({super.key});
  @override
  State<RemoteLoginPage> createState() => _RemoteLoginPageState();
}

class _RemoteLoginPageState extends State<RemoteLoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  final client = http.Client();
  bool busy = false;
  String? error;
  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await client
          .post(
            apiUri('/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.text.trim(),
              'password': password.text,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception();
      final token = (jsonDecode(response.body) as Map)['token'];
      if (token is! String || token.isEmpty) throw Exception();
      if (mounted) Navigator.of(context).pop(token);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '登录失败，请检查邮箱、密码或网络';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('登录')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: email,
          decoration: const InputDecoration(labelText: '邮箱'),
          keyboardType: TextInputType.emailAddress,
        ),
        TextField(
          controller: password,
          decoration: const InputDecoration(labelText: '密码'),
          obscureText: true,
        ),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy ? null : login,
          child: Text(busy ? '登录中' : '登录'),
        ),
      ],
    ),
  );
}
