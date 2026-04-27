class ServiceEndpoints {
  static const String ragAdminApi = 'https://rag-admin-api.rag.hierocracy.home';
  static const String llmGateway = '$ragAdminApi/api/chat';
  static const String ragIngestion = '$ragAdminApi/api/ingest'; // matched to admin-api proxy or expected path
  static const String objectStoreMgr = '$ragAdminApi/api/s3';
  static const String dbAdapter = '$ragAdminApi/api/db';
  static const String qdrantAdapter = '$ragAdminApi/api/qdrant';
  static const String memoryController = '$ragAdminApi/api/memory';
  static const String qdrantDirect = '$ragAdminApi/api/qdrant-direct';
  static const String grafana = '$ragAdminApi/api/grafana';
}
