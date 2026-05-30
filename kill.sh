#!/bin/bash
set -e

echo "Stopping and removing containers..."
docker-compose -f /root/task/docker-compose.yml down --volumes --remove-orphans || true

echo "Removing Docker images..."
docker rmi -f $(docker images -q | grep -E 'trading-fastapi|postgres:15-alpine' || true) || true

echo "System prune..."
docker system prune -a --volumes -f

echo "Cleaning app directory..."
rm -rf /root/task || true

echo "Cleanup completed successfully! Droplet is now clean."