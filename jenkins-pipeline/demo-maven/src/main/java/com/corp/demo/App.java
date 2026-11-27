package com.corp.demo;

import java.util.ArrayList;
import java.util.List;

/**
 * 演示用应用：一个极小的"订单金额计算 + 折扣"服务。
 * 每个方法都会参与静态扫描，用来演示 Sonar 质量门禁的效果。
 */
public class App {

    private static final double TAX_RATE = 0.06;

    public static void main(String[] args) {
        App app = new App();
        List<Double> items = new ArrayList<>();
        items.add(19.9);
        items.add(59.0);
        System.out.println("total=" + app.totalWithTax(items, 0.15));
    }

    /** 小计求和，负数视为 0。 */
    public double subtotal(List<Double> items) {
        if (items == null) {
            return 0.0;
        }
        double sum = 0.0;
        for (Double item : items) {
            if (item != null && item > 0) {
                sum += item;
            }
        }
        return round2(sum);
    }

    /** 折扣 + 6% 税，折扣率限制在 0~0.5。 */
    public double totalWithTax(List<Double> items, double discount) {
        double d = discount;
        if (d < 0) {
            d = 0;
        }
        if (d > 0.5) {
            d = 0.5;
        }
        double net = subtotal(items) * (1 - d);
        return round2(net * (1 + TAX_RATE));
    }

    private double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }
}
