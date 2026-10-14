#!/usr/bin/env bash
# Runs every linter against the deliberately bad code in src/demo/java and prints what each one found.
# Nothing here fails the build; the point is to compare the tools. Usage: scripts/run-demo.sh [mvn-command]
set -u
cd "$(dirname "$0")/.."
MVN="${1:-${MVN:-mvn}}"

count() { sort | uniq -c | sort -rn | awk '{printf "  %4d  %s\n", $1, $2}'; }

echo ">> compiling demo sources and running the report goals (Spotless last: it fails by design)"
$MVN -B -q -Pdemo -DskipTests compile \
  checkstyle:checkstyle pmd:pmd pmd:cpd spotbugs:spotbugs >target/demo-build.log 2>&1 \
  || { echo "build failed, see target/demo-build.log"; tail -20 target/demo-build.log; exit 1; }
$MVN -B -Pdemo spotless:check >target/spotless-demo.log 2>&1

echo; echo "== Checkstyle: conventions (target/checkstyle-result.xml)"
grep -o 'source="[^"]*"' target/checkstyle-result.xml | sed 's/.*\.//; s/Check"//; s/"//' | count

echo; echo "== PMD: code smells (target/pmd.xml)"
grep -o 'rule="[^"]*"' target/pmd.xml | sed 's/rule=//; s/"//g' | count
echo "   CPD copy/paste blocks: $(grep -c '<duplication' target/cpd.xml) (target/cpd.xml)"

echo; echo "== SpotBugs + Find Security Bugs: bug patterns (target/spotbugsXml.xml)"
grep -o "<BugInstance [^>]*type='[^']*'" target/spotbugsXml.xml | sed "s/.*type='//; s/'//" | count

echo; echo "== Spotless: files whose layout differs from google-java-format"
grep -E "^\[ERROR\]\s+src/" target/spotless-demo.log | sed 's/\[ERROR\] *//' | sort -u | sed 's/^/  /'
echo "   (fix them all with: mvn -Pdemo spotless:apply)"

echo; echo "SonarQube: run it separately, see README section 5."
