#!/bin/bash

BASE_URL="${1:-http://localhost:8000}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

ok()   { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

check_status() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  local body="$4"
  if [ "$actual" -eq "$expected" ]; then
    ok "$label (HTTP $actual)"
  else
    fail "$label — oczekiwano HTTP $expected, dostano $actual"
    echo "       body: $body"
  fi
}

echo "============================================"
echo "  Order System — smoke tests"
echo "  BASE_URL: $BASE_URL"
echo "============================================"
echo

# ── 1. Health ─────────────────────────────────────────────────────────────────

info "1. Health check"
RESP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
check_status "GET /health" 200 "$RESP"

# ── 2. Upload pliku ───────────────────────────────────────────────────────────

info "2. Upload pliku do S3"
echo "test file content $(date)" > /tmp/test_upload.txt
UPLOAD_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/upload" \
  -F "file=@/tmp/test_upload.txt;type=text/plain")
UPLOAD_STATUS=$(echo "$UPLOAD_RESP" | tail -1)
UPLOAD_BODY=$(echo "$UPLOAD_RESP" | head -1)
check_status "POST /upload" 200 "$UPLOAD_STATUS" "$UPLOAD_BODY"

FILE_ID=$(echo "$UPLOAD_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
S3_KEY=$(echo "$UPLOAD_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('s3_key',''))" 2>/dev/null)
info "  file_id=$FILE_ID  s3_key=$S3_KEY"

# ── 3. Lista uploadów ─────────────────────────────────────────────────────────

info "3. Lista uploadów"
LIST_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/uploads")
LIST_STATUS=$(echo "$LIST_RESP" | tail -1)
LIST_BODY=$(echo "$LIST_RESP" | head -1)
check_status "GET /uploads" 200 "$LIST_STATUS" "$LIST_BODY"

UPLOAD_COUNT=$(echo "$LIST_BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
info "  liczba plików w bazie: $UPLOAD_COUNT"

# ── 4. Download URL ───────────────────────────────────────────────────────────

if [ -n "$FILE_ID" ]; then
  info "4. Presigned URL do pobrania pliku"
  DL_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/uploads/$FILE_ID/download")
  DL_STATUS=$(echo "$DL_RESP" | tail -1)
  DL_BODY=$(echo "$DL_RESP" | head -1)
  check_status "GET /uploads/$FILE_ID/download" 200 "$DL_STATUS" "$DL_BODY"
  DL_URL=$(echo "$DL_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('url',''))" 2>/dev/null)
  info "  presigned URL: ${DL_URL:0:80}..."
else
  info "4. Pomijam download — brak file_id"
fi

# ── 5. Produkt z inventory ────────────────────────────────────────────────────

PRODUCT_ID="prod-001"
info "5. Pobranie produktu z inventory ($PRODUCT_ID)"
PROD_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/products/$PRODUCT_ID")
PROD_STATUS=$(echo "$PROD_RESP" | tail -1)
PROD_BODY=$(echo "$PROD_RESP" | head -1)
if [ "$PROD_STATUS" -eq 200 ] || [ "$PROD_STATUS" -eq 404 ]; then
  ok "GET /products/$PRODUCT_ID (HTTP $PROD_STATUS — serwis odpowiada)"
else
  fail "GET /products/$PRODUCT_ID — HTTP $PROD_STATUS"
  echo "       body: $PROD_BODY"
fi

# ── 6. Złożenie zamówienia ────────────────────────────────────────────────────

info "6. Złożenie zamówienia"
ORDER_BODY='{"customer_id":"customer-test-1","product_id":"PROD-001","quantity":2}'
ORDER_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/orders" \
  -H "Content-Type: application/json" \
  -d "$ORDER_BODY")
ORDER_STATUS=$(echo "$ORDER_RESP" | tail -1)
ORDER_RESP_BODY=$(echo "$ORDER_RESP" | head -1)
check_status "POST /orders" 200 "$ORDER_STATUS" "$ORDER_RESP_BODY"

ORDER_ID=$(echo "$ORDER_RESP_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
info "  order_id=$ORDER_ID"

# ── 7. Pobranie zamówienia ────────────────────────────────────────────────────

if [ -n "$ORDER_ID" ]; then
  info "7. Pobranie zamówienia po ID"
  GET_ORDER_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/orders/$ORDER_ID")
  GET_ORDER_STATUS=$(echo "$GET_ORDER_RESP" | tail -1)
  GET_ORDER_BODY=$(echo "$GET_ORDER_RESP" | head -1)
  check_status "GET /orders/$ORDER_ID" 200 "$GET_ORDER_STATUS" "$GET_ORDER_BODY"
  ORDER_STATUS_VAL=$(echo "$GET_ORDER_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)
  info "  status zamówienia: $ORDER_STATUS_VAL"
else
  info "7. Pomijam GET /orders/:id — brak order_id"
fi

# ── 8. Lista zamówień ─────────────────────────────────────────────────────────

info "8. Lista wszystkich zamówień"
ORDERS_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/orders")
ORDERS_STATUS=$(echo "$ORDERS_RESP" | tail -1)
ORDERS_BODY=$(echo "$ORDERS_RESP" | head -1)
check_status "GET /orders" 200 "$ORDERS_STATUS" "$ORDERS_BODY"
ORDERS_COUNT=$(echo "$ORDERS_BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
info "  liczba zamówień: $ORDERS_COUNT"

# ── 9. Płatność ───────────────────────────────────────────────────────────────

if [ -n "$ORDER_ID" ]; then
  info "9. Status płatności za zamówienie"
  PAY_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/payments/$ORDER_ID")
  PAY_STATUS=$(echo "$PAY_RESP" | tail -1)
  PAY_BODY=$(echo "$PAY_RESP" | head -1)
  if [ "$PAY_STATUS" -eq 200 ] || [ "$PAY_STATUS" -eq 404 ]; then
    ok "GET /payments/$ORDER_ID (HTTP $PAY_STATUS — serwis płatności odpowiada)"
    if [ "$PAY_STATUS" -eq 200 ]; then
      PAY_STATE=$(echo "$PAY_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)
      info "  status płatności: $PAY_STATE"
    fi
  else
    fail "GET /payments/$ORDER_ID — HTTP $PAY_STATUS"
    echo "       body: $PAY_BODY"
  fi
else
  info "9. Pomijam płatność — brak order_id"
fi

# ── 10. Zamówienie z plikiem (combo) ──────────────────────────────────────────

info "10. Zamówienie z załączonym plikiem (POST /orders/with-file)"
echo "order attachment $(date)" > /tmp/test_attachment.txt
COMBO_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/orders/with-file" \
  -F "customer_id=customer-test-2" \
  -F "product_id=PROD-002" \
  -F "quantity=1" \
  -F "file=@/tmp/test_attachment.txt;type=text/plain")
COMBO_STATUS=$(echo "$COMBO_RESP" | tail -1)
COMBO_BODY=$(echo "$COMBO_RESP" | head -1)
check_status "POST /orders/with-file" 200 "$COMBO_STATUS" "$COMBO_BODY"
if [ "$COMBO_STATUS" -eq 200 ]; then
  COMBO_ORDER_ID=$(echo "$COMBO_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('order',{}).get('id',''))" 2>/dev/null)
  COMBO_S3=$(echo "$COMBO_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('file',{}).get('s3_key',''))" 2>/dev/null)
  info "  order_id=$COMBO_ORDER_ID  s3_key=$COMBO_S3"
fi

# ── 11. Notyfikacje ───────────────────────────────────────────────────────────

info "11. Lista notyfikacji (DynamoDB)"
NOTIF_RESP=$(curl -s -w "\n%{http_code}" "$BASE_URL/notifications")
NOTIF_STATUS=$(echo "$NOTIF_RESP" | tail -1)
NOTIF_BODY=$(echo "$NOTIF_RESP" | head -1)
check_status "GET /notifications" 200 "$NOTIF_STATUS" "$NOTIF_BODY"
NOTIF_COUNT=$(echo "$NOTIF_BODY" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
info "  liczba notyfikacji: $NOTIF_COUNT"

# ── Podsumowanie ──────────────────────────────────────────────────────────────

echo
echo "============================================"
echo -e "  Wynik: ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC}"
echo "============================================"

[ "$FAIL" -eq 0 ]
