package store

import (
	"context"
	"errors"
	"time"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type Item struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

type Items struct {
	pool *pgxpool.Pool
}

func New(ctx context.Context, dsn string) (*Items, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	return &Items{pool: pool}, nil
}

func (s *Items) Close() {
	s.pool.Close()
}

func (s *Items) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

func (s *Items) Migrate(ctx context.Context) error {
	_, err := s.pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS items (
			id          TEXT PRIMARY KEY,
			name        TEXT NOT NULL,
			created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`)
	return err
}

func (s *Items) Insert(ctx context.Context, it Item) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO items (id, name, created_at) VALUES ($1, $2, $3)`,
		it.ID, it.Name, it.CreatedAt,
	)
	return err
}

func (s *Items) Get(ctx context.Context, id string) (Item, error) {
	var it Item
	err := s.pool.QueryRow(ctx,
		`SELECT id, name, created_at FROM items WHERE id = $1`, id,
	).Scan(&it.ID, &it.Name, &it.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Item{}, ErrNotFound
	}
	return it, err
}
