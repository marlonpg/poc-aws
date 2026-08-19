package com.pocaws.api.repository;

import com.pocaws.api.model.Item;

import java.util.List;
import java.util.Optional;

public interface ItemRepository {

    List<Item> findAll();

    Optional<Item> findById(String id);

    Item save(Item item);

    boolean deleteById(String id);
}
