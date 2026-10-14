package com.example.catalog.demo;

import java.util.Map;
import java.util.List;
import java.util.ArrayList;
import java.util.HashSet;

/**
 * SPOTLESS DEMO. Compiles and behaves fine, but is laid out differently from google-java-format.
 * `mvn -Pdemo spotless:check` lists every difference; `mvn -Pdemo spotless:apply` rewrites this file.
 */
public class FormatViolations
{
    private final Map<String,Integer> stock=new java.util.HashMap<>();   

    public List<String> names(Map<String,Integer>   input)
    {
        List<String> result=new ArrayList<>();
        for(String name:input.keySet()){ result.add(name); }
        if(result.isEmpty()){return List.of();}
        else{
            return result;
        }
    }

    public int total(){ int sum=0; for(int v:stock.values()){sum+=v;} return sum; }

    public String longCall(String alpha, String beta, String gamma, String delta, String epsilon, String zeta) {
        return String.join("-", alpha, beta, gamma, delta, epsilon, zeta, "and a long literal that pushes the line past one hundred characters");
    }
}
