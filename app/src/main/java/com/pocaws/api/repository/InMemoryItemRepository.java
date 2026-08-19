package com.pocaws.api.repository;

import com.pocaws.api.model.Item;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Repository
public class InMemoryItemRepository implements ItemRepository {

    private final Map<String, Item> items = new ConcurrentHashMap<>();

    @Override
    public List<Item> findAll() {
        return List.copyOf(items.values());
    }

    @Override
    public Optional<Item> findById(String id) {
        return Optional.ofNullable(items.get(id));
    }

    @Override
    public Item save(Item item) {
        items.put(item.id(), item);
        return item;
    }

    @Override
    public boolean deleteById(String id) {
        return items.remove(id) != null;
    }
}
