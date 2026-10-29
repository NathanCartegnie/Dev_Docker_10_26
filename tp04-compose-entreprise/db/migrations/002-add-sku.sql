ALTER TABLE products ADD COLUMN IF NOT EXISTS sku TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS products_sku_unique ON products (sku);
