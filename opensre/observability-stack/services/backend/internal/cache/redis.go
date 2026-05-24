package cache

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"

	"opensre.local/backend/internal/store"
)

type Cache struct {
	rdb *redis.Client
	ttl time.Duration
}

func New(addr string) (*Cache, error) {
	rdb := redis.NewClient(&redis.Options{Addr: addr})
	if err := redisotel.InstrumentTracing(rdb); err != nil {
		return nil, err
	}
	return &Cache{rdb: rdb, ttl: 5 * time.Minute}, nil
}

func (c *Cache) Close() error {
	return c.rdb.Close()
}

func (c *Cache) Ping(ctx context.Context) error {
	return c.rdb.Ping(ctx).Err()
}

func (c *Cache) GetItem(ctx context.Context, id string) (store.Item, bool, error) {
	raw, err := c.rdb.Get(ctx, key(id)).Bytes()
	if errors.Is(err, redis.Nil) {
		return store.Item{}, false, nil
	}
	if err != nil {
		return store.Item{}, false, err
	}
	var it store.Item
	if err := json.Unmarshal(raw, &it); err != nil {
		return store.Item{}, false, err
	}
	return it, true, nil
}

func (c *Cache) SetItem(ctx context.Context, it store.Item) error {
	raw, err := json.Marshal(it)
	if err != nil {
		return err
	}
	return c.rdb.Set(ctx, key(it.ID), raw, c.ttl).Err()
}

func key(id string) string { return "item:" + id }
