package com.example.catalog.demo;

import java.util.ArrayList;
import java.util.List;

/**
 * PMD + CPD + SONARQUBE DEMO. Code smells: legal, probably-working code that is hard to maintain.
 * Rule names in brackets are PMD rules; SonarQube reports the same issues with its own keys.
 */
public class SmellViolations {

  private String unusedField = "never read"; // [UnusedPrivateField] (Sonar S1068)

  private void neverCalled() {} // [UnusedPrivateMethod] (Sonar S1144)

  public List<String> find(String key) {
    if (key == null) {
      return null; // [ReturnEmptyCollectionRatherThanNull] (Sonar S1168)
    }
    int unused = 5; // [UnusedLocalVariable] (Sonar S1481)
    List<String> hits = new ArrayList<>();
    for (int i = 0; i < 3; i++) { // magic number 3 (Checkstyle MagicNumber)
      hits.add(key);
    }
    return hits;
  }

  public void report(String message) {
    System.out.println("report: " + message); // [SystemPrintln] (Sonar S106) use a logger
    try {
      Integer.parseInt(message);
    } catch (NumberFormatException e) {
      e.printStackTrace(); // [AvoidPrintStackTrace] (Sonar S1148)
    }
    try {
      Integer.parseInt(message);
    } catch (Exception e) { // [AvoidCatchingGenericException]
    } // [EmptyCatchBlock] (Sonar S108)
  }

  public boolean isPositive(int number) {
    if (number > 0) { // [SimplifyBooleanReturns] (Sonar S1126)
      return true;
    } else {
      return false;
    }
  }

  public String label(String kind) {
    // [AvoidDuplicateLiterals] "unknown" x4 (Sonar S1192)
    if (kind == null) {
      return "unknown";
    }
    if (kind.isEmpty()) {
      return "unknown";
    }
    if (kind.equals("?")) {
      return "unknown";
    }
    return kind.toLowerCase() + "unknown"; // [UseLocaleWithCaseConversions] (Sonar S1449)
  }

  /** Too many branches in one place: PMD CyclomaticComplexity / CognitiveComplexity (Sonar S3776). */
  public int shippingCost(String country, int weight, boolean express, boolean member) {
    int cost = 0;
    if ("RO".equals(country)) {
      if (weight < 5) {
        cost = express ? 10 : 5;
      } else if (weight < 20) {
        cost = express ? 20 : 12;
      } else {
        cost = express ? 40 : 25;
      }
    } else if ("DE".equals(country) || "FR".equals(country)) {
      if (weight < 5) {
        cost = express ? 15 : 9;
      } else {
        cost = express ? 30 : 18;
      }
    } else {
      cost = express ? 60 : 40;
    }
    if (member && cost > 10) {
      cost = cost - 5;
    }
    return cost;
  }

  // CPD (copy/paste detector): the next two methods are the same code with different names.
  public double priceWithVat(double net, String country) {
    double rate;
    if ("RO".equals(country)) {
      rate = 0.19;
    } else if ("DE".equals(country)) {
      rate = 0.19;
    } else if ("FR".equals(country)) {
      rate = 0.20;
    } else {
      rate = 0.0;
    }
    double vat = net * rate;
    double gross = net + vat;
    return Math.round(gross * 100.0) / 100.0;
  }

  public double invoiceWithVat(double net, String country) {
    double rate;
    if ("RO".equals(country)) {
      rate = 0.19;
    } else if ("DE".equals(country)) {
      rate = 0.19;
    } else if ("FR".equals(country)) {
      rate = 0.20;
    } else {
      rate = 0.0;
    }
    double vat = net * rate;
    double gross = net + vat;
    return Math.round(gross * 100.0) / 100.0;
  }

  public String joinAll(List<String> parts) {
    String joined = "";
    for (String part : parts) {
      joined += part + ","; // [UseStringBufferForStringAppends]: string += in a loop (Sonar S1643)
    }
    return joined;
  }

  // int oldCost = shippingCost("RO", 3, false, false);   <- commented-out code (Sonar S125)
}
