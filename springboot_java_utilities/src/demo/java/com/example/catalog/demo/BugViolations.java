package com.example.catalog.demo;

import java.io.FileReader;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Random;

/**
 * SPOTBUGS + FIND SECURITY BUGS DEMO. These are real defects visible in the bytecode: a style tool
 * cannot see them. Pattern names in brackets are what appears in target/spotbugsXml.xml.
 */
public class BugViolations {


  private final int[] limits = {1, 2, 3};

  public int[] limits() {
    return limits; // [EI_EXPOSE_REP] callers can mutate our internal array
  }

  public Connection connect() throws SQLException {
    return DriverManager.getConnection("jdbc:h2:mem:demo", "admin", "s3cr3t-admin-password"); // [HARD_CODE_PASSWORD]
  }

  public String findUser(Connection connection, String name) throws SQLException {
    Statement statement = connection.createStatement();
    // [SQL_INJECTION_JDBC] name = "x' OR '1'='1" returns every user
    var rows = statement.executeQuery("select * from users where name = '" + name + "'");
    return rows.next() ? rows.getString(1) : null;
  }

  public int firstLineLength(String path) throws IOException {
    FileReader reader = new FileReader(path); // [PATH_TRAVERSAL_IN] + [OS_OPEN_STREAM] never closed
    return reader.read();
  }

  public byte[] fingerprint(String text) throws NoSuchAlgorithmException {
    return MessageDigest.getInstance("MD5").digest(text.getBytes()); // [WEAK_MESSAGE_DIGEST_MD5] [IMPROPER_UNICODE] [DM_CONVERT_CASE]-family
  }

  public int sessionToken() {
    return new Random().nextInt(); // [PREDICTABLE_RANDOM] [DMI_RANDOM_USED_ONLY_ONCE]
  }

  public boolean isAdmin(String role) {
    String expected = new String("admin"); // [DM_STRING_CTOR]
    return role == expected; // [ES_COMPARING_PARAMETER_STRING_WITH_EQ]
  }

  public int lengthOrCrash(String maybeNull) {
    if (maybeNull == null) {
      System.out.println("value was null");
    }
    return maybeNull.length(); // [NP_NULL_ON_SOME_PATH] dereferenced after the null check above
  }

  public String shout(String text) {
    text.toUpperCase(); // [RV_RETURN_VALUE_IGNORED] strings are immutable
    return text;
  }

  /** Overrides equals but not hashCode: breaks HashMap/HashSet. */
  public static class Money {
    private final long cents;

    public Money(long cents) {
      this.cents = cents;
    }

    @Override
    public boolean equals(Object other) { // [HE_EQUALS_USE_HASHCODE]
      return other instanceof Money m && m.cents == cents;
    }
  }

  public Process run(String userInput) throws IOException {
    return Runtime.getRuntime().exec("ls " + userInput); // [COMMAND_INJECTION]
  }
}
