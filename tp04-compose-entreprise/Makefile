.PHONY: up prod-up migrate test down

up:
	docker compose up -d --build --wait

prod-up:
	docker compose -f compose.yml -f compose.prod.yml up -d --wait

migrate:
	MIGRATION=$(M) docker compose run --rm migrate

test:
	bash ./smoke-test.sh

down:
	docker compose down
