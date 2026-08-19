package com.pocaws.api.model;

import java.time.Instant;

public record Item(String id, String name, Instant createdAt) {
}
