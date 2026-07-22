class ApiConfig {
  const ApiConfig._();

  static const String host = '52.220.128.244:8001';

  static const String restBaseUrl = 'http://$host/api/v1';
  static const String webSocketBaseUrl = 'ws://$host';

  static const String loginPath = '/users/login';
}
