mod common;
use common::*;
use constellation_core::VaultIndex;
use std::collections::BTreeMap;
use std::fs;
use std::time::Instant;

fn paths(r: &constellation_core::search::Results) -> Vec<&str> {
    r.matches.iter().map(|m| m.path.as_str()).collect()
}

fn units(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

fn sub16(s: &str, loc: usize, len: usize) -> String {
    String::from_utf16(&units(s)[loc..loc + len]).unwrap()
}

#[test]
fn folds_case_and_diacritics_and_groups_results() {
    let v = make_vault(&[
        ("Applications/overview.md", "Nothing here."),
        ("cafe-notes.md", "We met at the Café on Friday. Bring the budget."),
        ("Résumé.md", "Plain text."),
    ]);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.search("application").folders, ["Applications"]);
    assert_eq!(ix.search("resume").notes, ["Résumé.md"]);
    let r = ix.search("CAFE");
    assert_eq!(r.notes, ["cafe-notes.md"]);
    assert_eq!(r.matches.len(), 1);
    assert_eq!(r.matches[0].path, "cafe-notes.md");
    assert_eq!(r.matches[0].sentence, "We met at the Café on Friday.");
    assert_eq!(sub16(&r.matches[0].sentence, r.matches[0].hit.location, r.matches[0].hit.length), "Café");
}

#[test]
fn sentence_and_offset_point_at_the_hit() {
    let text = "# Title\n\nFirst sentence. The deadline moves! Last one?";
    let v = make_vault(&[("a.md", text)]);
    let m = VaultIndex::open(v.path()).unwrap().search("deadline").matches;
    assert_eq!(m.iter().map(|m| m.sentence.as_str()).collect::<Vec<_>>(), ["The deadline moves!"]);
    assert_eq!(sub16(text, m[0].offset, 8), "deadline");
}

#[test]
fn offsets_count_utf16_units_after_emoji_and_accents() {
    let text = "Ünï 😀😀 first line.\nSecond 😀 Straße here, and the café bar.";
    let v = make_vault(&[("a.md", text)]);
    let ix = VaultIndex::open(v.path()).unwrap();
    for (q, shown) in [("strasse", "Straße"), ("cafe", "café"), ("second", "Second")] {
        let m = &ix.search(q).matches[0];
        assert_eq!(sub16(text, m.offset, units(shown).len()), shown, "{q}");
        assert_eq!(sub16(&m.sentence, m.hit.location, m.hit.length), shown, "{q}");
    }
    assert_eq!(ix.search("second").matches[0].sentence, "Second 😀 Straße here, and the café bar.");
}

#[test]
fn app_only_files_and_folders_are_excluded() {
    let v = make_vault(&[
        ("AGENTS.md", "secret rule"),
        ("templates/daily.md", "secret template"),
        ("tags.md", "secret"),
        ("pub.md", "visible secret"),
    ]);
    let ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(paths(&ix.search("secret")), ["pub.md"]);
    assert!(ix.search("templates").folders.is_empty());
    assert!(ix.search("agents").notes.is_empty());
}

#[test]
fn ingest_applies_create_edit_delete_and_folder_removal() {
    let v = make_vault(&[("a.md", "alpha"), ("dir/b.md", "beta")]);
    let mut ix = VaultIndex::open(v.path()).unwrap();
    assert_eq!(ix.search("beta").matches.len(), 1);

    write(v.path(), "a.md", "gamma");
    write(v.path(), "new/c.md", "gamma too");
    ix.ingest(&["a.md".into(), "new/c.md".into()]).unwrap();
    assert!(ix.search("alpha").matches.is_empty());
    let mut got = paths(&ix.search("gamma")).into_iter().map(String::from).collect::<Vec<_>>();
    got.sort();
    assert_eq!(got, ["a.md", "new/c.md"]);
    assert_eq!(ix.search("new").folders, ["new"]);

    fs::remove_dir_all(v.path().join("dir")).unwrap();
    ix.ingest(&["dir".into()]).unwrap();
    assert!(ix.search("beta").matches.is_empty());
    assert!(ix.search("dir").folders.is_empty());
    assert!(ix.search("b.md").notes.is_empty());
}

#[test]
fn hits_after_length_changing_folds_map_back_to_the_original_text() {
    // "ß" folds to "ss" (longer) and a decomposed "é" to "e" (shorter); matches after them must still point at the original.
    let text = "Die Straße ist lang. Cafe\u{301} am Eck. Der Termin steht.";
    let v = make_vault(&[("a.md", text)]);
    let ix = VaultIndex::open(v.path()).unwrap();
    for (q, shown) in [("strasse", "Straße"), ("cafe", "Cafe\u{301}"), ("termin", "Termin")] {
        let m = &ix.search(q).matches[0];
        assert_eq!(sub16(text, m.offset, units(shown).len()), shown, "{q}");
        assert_eq!(sub16(&m.sentence, m.hit.location, m.hit.length), shown, "{q}");
    }
    assert_eq!(ix.search("termin").matches[0].sentence, "Der Termin steht.");
    assert_eq!(ix.search("lang").matches[0].sentence, "Die Straße ist lang.");
}

#[test]
fn archive_notes_are_marked() {
    let v = make_vault(&[("shop/README.md", "# Shop"), ("shop/archive/fixed-bugs.md", "### Cache bug\n- what: stale cache\n")]);
    let r = VaultIndex::open(v.path()).unwrap().search("stale");
    assert!(r.notes.is_empty());
    assert_eq!(paths(&r), ["shop/archive/fixed-bugs.md"]);
    assert!(r.is_archived("shop/archive/fixed-bugs.md"));
    assert!(!r.is_archived("shop/README.md"));
    assert_eq!(r.archived, ["shop/archive/fixed-bugs.md"]);
}

#[test]
fn tag_term_filters_and_combines_with_text() {
    let v = make_vault(&[
        ("z.md", "nothing"),
        ("a.md", "Refund policy #payments"),
        ("b.md", "Refund for travel"),
        ("c.md", "Invoices #Payments/eu"),
    ]);
    let s = VaultIndex::open(v.path()).unwrap();
    let r = s.search("#payments refund");
    assert!(r.notes.is_empty());
    assert_eq!(paths(&r), ["a.md"]);
    assert_eq!(s.search("#PAYMENTS").notes, ["a.md", "c.md"]);
    assert_eq!(s.search("refund").matches.len(), 2);
}

#[test]
fn benchmark_5000_notes() {
    let files: BTreeMap<String, String> = (0..5000)
        .map(|i| {
            let text = (0..10).map(|s| format!("Sentence {s} of note {i} talks about topic{}.", s * i % 97)).collect::<Vec<_>>().join(" ");
            (format!("f{}/note-{i}.md", i % 50), text)
        })
        .collect();
    let v = make_vault(&files.iter().map(|(p, t)| (p.as_str(), t.as_str())).collect::<Vec<_>>());
    let ix = VaultIndex::open(v.path()).unwrap();
    // A rare word, and one in every Note (all hits get sorted: that used to take ~80 ms).
    for q in ["topic42", "note"] {
        let start = Instant::now();
        let r = ix.search(q);
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        assert!(!r.matches.is_empty());
        // The 50 ms budget is for release builds; unoptimized code only has to stay usable.
        assert!(ms < if cfg!(debug_assertions) { 1000.0 } else { 50.0 }, "{q}: {ms} ms");
    }
}
