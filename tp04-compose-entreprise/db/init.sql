CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0)
);

INSERT INTO products (id, name, price, stock) VALUES
    (1, 'Clavier mécanique', 89.90, 12),
    (2, 'Écran 27 pouces', 249.00, 4),
    (3, 'Souris sans fil', 29.50, 40)
ON CONFLICT (id) DO NOTHING;

SELECT setval(
    pg_get_serial_sequence('products', 'id'),
    GREATEST((SELECT COALESCE(MAX(id), 1) FROM products), 1)
);

CREATE TABLE IF NOT EXISTS orders (
    id BIGSERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
