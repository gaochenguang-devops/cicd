package com.corp.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

class AppTest {

    private final App app = new App();

    @Test
    void subtotalSumsPositiveItems() {
        List<Double> items = Arrays.asList(10.0, 20.5, -5.0, null);
        assertEquals(30.5, app.subtotal(items));
    }

    @Test
    void subtotalHandlesNull() {
        assertEquals(0.0, app.subtotal(null));
    }

    @Test
    void totalAppliesDiscountAndTax() {
        List<Double> items = Arrays.asList(100.0);
        assertEquals(90.1, app.totalWithTax(items, 0.15));
    }

    @Test
    void totalClampsDiscount() {
        List<Double> items = Arrays.asList(100.0);
        assertEquals(53.0, app.totalWithTax(items, 0.9));
    }
}
