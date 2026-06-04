const String API_BASE_URL = "https://zydus.mediola.in/pod_dev/api/";
//const String API_BASE_URL = "https://zydus.mediola.in/development/api/";
// USB-tethered device via `adb reverse tcp:8000 tcp:8000` — phone's
// localhost:8000 tunnels to this PC. No Wi-Fi/firewall dependency.
//const String API_BASE_URL = "http://localhost:8000/api/";
//const String API_BASE_URL = "http://192.168.1.19:8000/api/";
//const String API_BASE_URL = "http://192.168.1.140:8000/api/";
//const String API_BASE_URL = "http://192.168.0.122:8000/api/";

const String API_DOC_UPLOAD_URL = "${API_BASE_URL}grn/upload-pdf";
const String API_POD_UPLOAD_URL = "${API_BASE_URL}pod/upload-pdf";
// const String Multi_Api_POD_UPLOAD_URL = "${API_BASE_URL}pod/multi-upload-pdf";
const String Multi_Api_POD_UPLOAD_URL =
    "${API_BASE_URL}split-file-processor/process";
// Image-friendly endpoint used when the batch contains any non-PDF file
// (JPG/JPEG/PNG). The default endpoint above is PDF-only because it calls
// an external split-pdf API.
const String Multi_Api_POD_UPLOAD_URL_IMAGES =
    "${API_BASE_URL}pod/upload-multi-allow-images";

const String API_GRNS_URL = "${API_BASE_URL}grns";
const String API_EINV_JSON_URL = "${API_BASE_URL}einv/json";
const String API_STOCKISTS_URL = "${API_BASE_URL}stockists";
const String API_HOSPITALS_URL = "${API_BASE_URL}hospitals";
const String API_LOGIN_URL = "${API_BASE_URL}session/create";
const String API_PODS_URL = "${API_BASE_URL}pods";
const String API_NOTIFICATIONS_URL = "${API_BASE_URL}notifications";
const String API_BATCHES_URL = "${API_BASE_URL}batches";
