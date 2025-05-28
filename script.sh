kubectl set image deployment trouble-box trouble-box=busybox:develop -n ns-48414609
kubectl delete pod -l app=trouble-box -n ns-48414609

kubectl patch deployment trouble-box -n ns-52327214 \
  --type=json \
  -p='[{
    "op": "replace",
    "path": "/spec/template/spec/volumes/0/persistentVolumeClaim/claimName",
    "value": "processing-backoffice-pvc"
  }]'

sleep 2

kubectl delete pod -l app=trouble-box -n ns-52327214

kubectl exec -n ns-94714545 deploy/trouble-box -- /bin/sh -c "kill 1"

kubectl patch cronjob orders-cleanup -n ns-94714545 \
  --type=merge \
  -p '{"spec":{"suspend":true}}'

kubectl patch cronjob orders-cleanup -n ns-48414609\
  --type=merge \
  -p '{"spec":{"suspend":true}}'

kubectl exec -n ns-48414609 deploy/trouble-box -- \
  /bin/sh -c "dd if=/dev/zero of=/app/orders/fill90 bs=1M count=1950"

curl -X POST http://localhost:8000/load/cpu/nightmare
curl -X POST http://localhost:8001/load/memory/nightmare
for i in {1..50}; do curl -X POST http://localhost:8002/order/hardcore & done

curl -X 'POST' \
  'http://localhost:8001/killswitch' \
  -H 'accept: application/json' \
  -d ''
