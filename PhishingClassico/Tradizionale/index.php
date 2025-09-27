<?php

$env_ngrok = getenv('NGROK_URL');
if ($env_ngrok !== false && $env_ngrok !== '') {
    $ngrok_url = 'http://localhost:5001'; // local
}

$destination_url = $ngrok_url . $_SERVER['REQUEST_URI'];

$ch = curl_init();

curl_setopt($ch, CURLOPT_URL, $destination_url);

$forward_headers = [];
foreach (getallheaders() as $h => $v) {
    if (strtolower($h) === 'host') continue;
    $forward_headers[] = "$h: $v";
}
$forward_headers[] = 'ngrok-skip-browser-warning: true';
if (!empty($forward_headers)) {
    curl_setopt($ch, CURLOPT_HTTPHEADER, $forward_headers);
}

curl_setopt($ch, CURLOPT_USERAGENT, isset($_SERVER['HTTP_USER_AGENT']) ? $_SERVER['HTTP_USER_AGENT'] : 'Mozilla/5.0');
curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
curl_setopt($ch, CURLOPT_ENCODING, '');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
curl_setopt($ch, CURLOPT_TIMEOUT, 20);

curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);

$method = $_SERVER['REQUEST_METHOD'];
if ($method === 'POST' || $method === 'PUT' || $method === 'PATCH') {
    $body = file_get_contents('php://input');
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
}

$resp = curl_exec($ch);

if (curl_errno($ch)) {
    $err = curl_error($ch);
    @file_put_contents(__DIR__ . '/debug/ngrok.log', "[" . date('c') . "] cURL error: $err\n", FILE_APPEND);
    echo 'Errore cURL: ' . htmlspecialchars($err);
    curl_close($ch);
    exit;
}

$header_size = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$header_text = substr($resp, 0, $header_size);
$body = substr($resp, $header_size);
$headers = preg_split("/\r?\n/", $header_text);
$response_headers = [];
foreach ($headers as $hline) {
    if (strpos($hline, ':') !== false) {
        list($hn, $hv) = explode(':', $hline, 2);
        $response_headers[trim($hn)] = trim($hv);
    }
}

if (!empty($response_headers['Location'])) {
    header('Location: ' . $response_headers['Location']);
    curl_close($ch);
    exit;
}

foreach ($response_headers as $hn => $hv) {
    if (in_array(strtolower($hn), ['transfer-encoding', 'content-encoding'])) continue;
    header("$hn: $hv");
}

echo $body;

curl_close($ch);

?>
