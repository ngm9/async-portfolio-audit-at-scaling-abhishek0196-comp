#!/bin/bash
set -e
cd /root/task
echo "Starting trading app containers..."
docker-compose up -d
echo "Waiting for PostgreSQL to start..."
for i in {1..30}; do
  docker exec trading-postgres pg_isready -U traderadmin && break
  sleep 2
done
sleep 3
for i in {1..10}; do
  curl -sf http://localhost:8000/docs && break
  sleep 2
done
echo "Trading API and Postgres ready!"