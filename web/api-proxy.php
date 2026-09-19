<?php
// High-performance API reverse proxy for Node.js / Hono backend on Hostinger
// Supports REST, JSON, multipart uploads, custom headers, and status code passthrough

$targetPort = getenv('BACKEND_PORT') ? (int)getenv('BACKEND_PORT') : 3000;

// Allow override file in same directory if PORT is specified
if (file_exists(__DIR__ . '/.backend_port')) {
    $raw = file_get_contents(__DIR__ . '/.backend_port');
    $clean = preg_replace('/[^0-9]/', '', $raw);
    $customPort = (int)$clean;
    if ($customPort > 0) {
        $targetPort = $customPort;
    }
}

$backendHost = "http://127.0.0.1:{$targetPort}";
// Handle CORS preflight immediately
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, x-firebase-token, apikey, Range, X-Requested-With, Origin, Accept');
    header('Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges, Retry-After');
    header('Access-Control-Max-Age: 86400');
    http_response_code(204);
    exit;
}

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, x-firebase-token, apikey, Range, X-Requested-With, Origin, Accept');
header('Access-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges, Retry-After');

$ch = curl_init($targetUrl);

// Forward all incoming request headers except Host
$incomingHeaders = [];
if (function_exists('getallheaders')) {
    foreach (getallheaders() as $key => $value) {
        $lower = strtolower($key);
        if ($lower === 'host' || $lower === 'content-length') {
            continue;
        }
        $incomingHeaders[] = "{$key}: {$value}";
    }
} else {
    foreach ($_SERVER as $key => $value) {
        if (substr($key, 0, 5) === 'HTTP_') {
            $header = str_replace(' ', '-', ucwords(str_replace('_', ' ', strtolower(substr($key, 5)))));
            if (strtolower($header) !== 'host') {
                $incomingHeaders[] = "{$header}: {$value}";
            }
        }
    }
}

// Ensure Content-Type is forwarded if provided in $_SERVER['CONTENT_TYPE']
if (isset($_SERVER['CONTENT_TYPE']) && !empty($_SERVER['CONTENT_TYPE'])) {
    $hasContentType = false;
    foreach ($incomingHeaders as $h) {
        if (stripos($h, 'Content-Type:') === 0) {
            $hasContentType = true;
            break;
        }
    }
    if (!$hasContentType) {
        $incomingHeaders[] = 'Content-Type: ' . $_SERVER['CONTENT_TYPE'];
    }
}

// Get the real client IP (supporting Cloudflare, reverse proxies, and direct connections)
$clientIp = $_SERVER['HTTP_CF_CONNECTING_IP'] 
    ?? (isset($_SERVER['HTTP_X_FORWARDED_FOR']) ? trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0]) : null)
    ?? $_SERVER['HTTP_X_REAL_IP'] 
    ?? $_SERVER['REMOTE_ADDR'] 
    ?? '127.0.0.1';

$incomingHeaders[] = 'X-Forwarded-For: ' . $clientIp;
$incomingHeaders[] = 'X-Real-IP: ' . $clientIp;
$incomingHeaders[] = 'X-Forwarded-Proto: ' . ((isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https' : 'http');
$incomingHeaders[] = 'X-Forwarded-Host: ' . ($_SERVER['HTTP_HOST'] ?? 'localhost');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

curl_setopt($ch, CURLOPT_HTTPHEADER, $incomingHeaders);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 60);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 5);

// Forward body for methods that send payload
if (in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'])) {
    $body = file_get_contents('php://input');
    if ($body !== false && strlen($body) > 0) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    }
}

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);

if ($response !== false) {
    $rawHeaders = substr($response, 0, $headerSize);
    $responseBody = substr($response, $headerSize);

    foreach (explode("\r\n", $rawHeaders) as $headerLine) {
        $trimmed = trim($headerLine);
        if ($trimmed && 
            !preg_match('/^Transfer-Encoding:/i', $trimmed) && 
            !preg_match('/^Connection:/i', $trimmed) && 
            !preg_match('/^HTTP\//i', $trimmed)) {
            header($trimmed, false);
        }
    }

    if ($httpCode) {
        http_response_code($httpCode);
    }
    echo $responseBody;
} else {
    http_response_code(502);
    header('Content-Type: application/json');
    echo json_encode([
        'error' => 'Bad Gateway',
        'message' => 'Backend service is unavailable',
        'backendPort' => $targetPort,
        'curlError' => curl_error($ch)
    ]);
}

curl_close($ch);
