package com.example.catalog.demo;

// CHECKSTYLE DEMO. Every problem below is a convention breach, not a bug: the code works.
// Expected findings are listed per line as  [CheckName]  (run scripts/run-demo.sh checkstyle).

import java.io.File; // [UnusedImports] never used
import java.util.*; // [AvoidStarImport]

public class StyleViolations { // [MissingJavadocType] no Javadoc on a public class

  public static final int maxItems = 5; // [ConstantName] constants are UPPER_SNAKE_CASE
  public String publicField = "x"; // [VisibilityModifier] fields should be private
  private int Counter; // [MemberName] members are lowerCamelCase

  public int Compute(int a, int b, int c, int d, int e, int f) { // [MethodName] [ParameterNumber] 6 > 5
    int total = a * 42 + b * 7; // [MagicNumber] 42 and 7
    int x = 1, y = 2; // [MultipleVariableDeclarations]
    if (total > 10) return total; // [NeedBraces]
    x = y = 3; // [InnerAssignment]
    long big = 100l; // [UpperEll] 100l reads like 1001
    return total + x + y + (int) big;
  }

  public String describe(int code) {
    switch (code) { // [MissingSwitchDefault]
      case 1:
        return "one";
      case 2:
        return "two";
    }
    return "many";
  }

  public boolean sameName(String left, String right) {
    return left == "admin"; // [StringLiteralEquality] compares references, not text
  }

  public void swallow() {
    try {
      Integer.parseInt("not a number");
    } catch (Exception e) { // [IllegalCatch] too broad
      // [EmptyCatchBlock] error silently dropped
    }
  }

  // TODO: remove this class before release [TodoComment] (warning only, does not fail)

  public int deeplyNested(int a, int b, int c) {
    if (a > 0) {
      if (b > 0) {
        if (c > 0) { // [NestedIfDepth] depth 3 > 2
          if (a > b && b > c || c > a && a > 0 && b > 0) { // [BooleanExpressionComplexity]
            return 1;
          }
        }
      }
    }
    return 0;
  }

  public String aVeryLongMethodWithAnExtremelyDescriptiveNameThatKeepsGoing(String firstArgument, String secondArgument) { // [LineLength] > 100 columns
    return firstArgument + secondArgument;
  }
}
