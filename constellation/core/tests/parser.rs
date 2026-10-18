mod common;
use common::at16;
use constellation_core::parser::{parse, typed_tag_prefix};
use constellation_core::Range16;
use std::collections::BTreeMap;

fn names(text: &str) -> Vec<String> {
    parse(text).tags.into_iter().map(|t| t.name).collect()
}

fn map(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
    pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
}

const CART: &str = "---\ntype: endpoint\nowner: team-a\n---\n# Cart endpoints\n\n## GET /cart\nCalls:\n- [[shop-orders/endpoints#POST /orders]]\n- [[shop-orders/endpoints#GET /stock]]\n\nStatus:\n- implemented: true\n- last_changed: 2026-01-02\n\n## DELETE /cart\nCalls:\n- [[shop-orders/endpoints#POST /orders]]";

#[test]
fn finds_links_with_heading_and_alias() {
    let text = "See [[api]], [[overview#Goals]] and [[notes|the notes]] or [[a/b#H|x]].";
    let links = parse(text).links;
    assert_eq!(links.iter().map(|l| l.target.as_str()).collect::<Vec<_>>(), ["api", "overview", "notes", "a/b"]);
    assert_eq!(links.iter().map(|l| l.heading.as_deref()).collect::<Vec<_>>(), [None, Some("Goals"), None, Some("H")]);
    assert_eq!(links.iter().map(|l| l.alias.as_deref()).collect::<Vec<_>>(), [None, None, Some("the notes"), Some("x")]);
    assert_eq!(links[0].range, Range16::new(4, 7));
}

#[test]
fn links_in_code_are_ignored() {
    let links = parse("`[[inline]]`\n```\n[[fenced]]\n```\n[[real]]").links;
    assert_eq!(links.iter().map(|l| l.target.as_str()).collect::<Vec<_>>(), ["real"]);
}

#[test]
fn finds_headings_outside_code() {
    let text = "# One\n```\n# not\n```\n## Two\n";
    let hs = parse(text).headings;
    assert_eq!(hs.iter().map(|h| h.title.as_str()).collect::<Vec<_>>(), ["One", "Two"]);
    assert_eq!(hs.iter().map(|h| h.level).collect::<Vec<_>>(), [1, 2]);
    assert_eq!(hs[1].range, Range16::new(text.find("## Two").unwrap(), 6));
}

#[test]
fn tags_valid_and_invalid_forms() {
    assert_eq!(names("Ship it #release and #team/payments now"), ["release", "team/payments"]);
    assert_eq!(names("#first at line start"), ["first"]);
    assert!(names("# Heading\n## Another\n#123 #fff #FF00aa #1st").is_empty());
    assert!(names("See https://example.com/page#section and a#b and `#code`").is_empty());
    assert!(names("[jump](#intro) and [[Note#Head]]").is_empty());
    assert_eq!(names("```\n#fenced\n```\n#real"), ["real"]);
}

#[test]
fn tag_range_covers_hash_and_name() {
    assert_eq!(parse("ab #team/x!").tags[0].range, Range16::new(3, 7));
}

#[test]
fn frontmatter_tags() {
    assert_eq!(names("---\ntitle: x\ntags: [alpha, \"beta\", #gamma]\n---\nbody #delta"), ["alpha", "beta", "gamma", "delta"]);
    assert_eq!(names("---\ntags:\n  - one\n  - two/sub\nother: y\n  - notatag\n---\n"), ["one", "two/sub"]);
    assert_eq!(names("---\ntags: a, b\n---"), ["a", "b"]);
    assert!(names("text\n---\ntags: [nope]\n---").is_empty());
}

/// Swift found the first "a" of `tags: a, b` inside the word "tags", so the range was wrong.
#[test]
fn frontmatter_tag_ranges_point_at_the_tag() {
    let text = "---\ntags: a, [bb]\n  - x\n---\n";
    let tags = parse(text).tags;
    assert_eq!(tags.iter().map(|t| t.range).collect::<Vec<_>>(), [Range16::new(10, 1), Range16::new(14, 2), Range16::new(22, 1)]);
    let text = "---\ntags:\n  - one\n---\n";
    assert_eq!(parse(text).tags[0].range, Range16::new(text.find("one").unwrap(), 3));
}

#[test]
fn typed_tag_prefix_cases() {
    assert_eq!(typed_tag_prefix("see #te").as_deref(), Some("te"));
    assert_eq!(typed_tag_prefix("# te"), None);
    assert_eq!(typed_tag_prefix("a#te"), None);
}

#[test]
fn offsets_are_utf16_code_units() {
    let text = "é😀 #tag [[x]] and a#nope\n## Hé\n";
    let p = parse(text);
    assert_eq!(p.tags.len(), 1);
    assert_eq!(p.tags[0].range, Range16::new(4, 4));
    assert_eq!(p.links[0].range, Range16::new(9, 5));
    assert_eq!(p.headings[0].range.location, text.encode_utf16().count() - 6);
    assert_eq!(p.headings[0].range.length, 5);
}

#[test]
fn note_types_and_unknown_keys() {
    let p = parse(CART);
    assert_eq!(p.note_type, "endpoint");
    assert_eq!(p.frontmatter["owner"], "team-a");
    assert_eq!(p.headings.iter().map(|h| h.title.as_str()).collect::<Vec<_>>(), ["Cart endpoints", "GET /cart", "DELETE /cart"]);
    assert_eq!(parse("plain").note_type, "note");
    let odd = parse("---\ntype: gizmo\nx: 1\n---\nbody");
    assert_eq!(odd.note_type, "gizmo");
    assert_eq!(odd.frontmatter["x"], "1");
}

#[test]
fn calls_per_endpoint_and_status() {
    let p = parse(CART);
    assert_eq!(p.calls.iter().map(|c| c.heading.title.as_str()).collect::<Vec<_>>(), ["GET /cart", "DELETE /cart"]);
    assert_eq!(p.calls[0].links.iter().map(|l| l.heading.as_deref().unwrap()).collect::<Vec<_>>(), ["POST /orders", "GET /stock"]);
    assert_eq!(p.status[0].values, map(&[("implemented", "true"), ("last_changed", "2026-01-02")]));
}

#[test]
fn calls_outside_endpoint_heading_is_a_plain_list() {
    let p = parse("# Misc\nCalls:\n- [[a]]\n## GET /x\nCalls:\n- [[b#GET /y]]");
    assert_eq!(p.calls.iter().map(|c| c.heading.title.as_str()).collect::<Vec<_>>(), ["GET /x"]);
    assert_eq!(p.links.iter().map(|l| l.target.as_str()).collect::<Vec<_>>(), ["a", "b"]);
}

#[test]
fn uses_only_in_client_notes() {
    let web = "---\ntype: client\n---\n# Web\nUses:\n- [[shop-cart/endpoints#GET /cart]]\n";
    assert_eq!(parse(web).uses[0].links[0].target, "shop-cart/endpoints");
    assert!(parse("# W\nUses:\n- [[a#GET /x]]").uses.is_empty());
}

#[test]
fn endpoint_heading_under_cursor() {
    let p = parse(CART);
    assert_eq!(p.endpoint_heading(at16(CART, "[[shop-orders/endpoints#GET")).unwrap().title, "GET /cart");
    assert!(p.endpoint_heading(0).is_none());
    assert!(p.endpoint_heading(at16(CART, "# Cart") + 3).is_none());
}

#[test]
fn calls_belong_to_the_enclosing_endpoint_across_sub_headings() {
    let p = parse("## GET /a\n### Request\nCalls:\n- [[b#GET /b]]\n## Notes\nCalls:\n- [[c#GET /c]]\n");
    assert_eq!(p.calls.iter().map(|c| c.heading.title.as_str()).collect::<Vec<_>>(), ["GET /a"]);
    assert_eq!(p.calls[0].links[0].target, "b");
    let text = "## GET /a\n### Request\nbody\n## Notes\nmore";
    let q = parse(text);
    assert_eq!(q.endpoint_heading(at16(text, "body")).unwrap().title, "GET /a");
    assert!(q.endpoint_heading(at16(text, "more")).is_none());
}

#[test]
fn calls_accept_trailing_spaces_indented_bullets_and_backticked_methods() {
    let p = parse("## `GET /a`\nCalls: \t\n  - [[b#GET /b]]\n\t* [[c#GET /c]]\nStatus:\n  - implemented: true\n");
    assert_eq!(p.calls.iter().map(|c| c.heading.title.as_str()).collect::<Vec<_>>(), ["`GET /a`"]);
    assert_eq!(p.calls[0].links.iter().map(|l| l.target.as_str()).collect::<Vec<_>>(), ["b", "c"]);
    assert_eq!(p.status[0].values, map(&[("implemented", "true")]));
}

#[test]
fn json_shape_is_camel_case_with_type() {
    let v = serde_json::to_value(parse("---\ntype: repo\n---\n[[a#H|x]]")).unwrap();
    assert_eq!(v["type"], "repo");
    assert_eq!(v["links"][0]["range"]["location"], 19);
    assert_eq!(v["links"][0]["alias"], "x");
}

#[test]
fn hash_inside_wiki_link_is_not_a_tag() {
    assert!(names("See [[#Sec]] and [[#Sec|alias]].").is_empty());
    assert_eq!(names("[[#Sec]] #real"), ["real"]);
}
