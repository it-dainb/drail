//! Shared tree-sitter utilities used by symbol search and caller search.

/// Definition node kinds across tree-sitter grammars.
pub(crate) const DEFINITION_KINDS: &[&str] = &[
    // Functions
    "function_declaration",
    "function_definition",
    "function_item",
    "method_definition",
    "method_declaration",
    // Classes & structs
    "class_declaration",
    "class_definition",
    "struct_item",
    // Interfaces & types (TS)
    "interface_declaration",
    "trait_declaration",
    "type_alias_declaration",
    "type_item",
    // Enums
    "enum_item",
    "enum_declaration",
    // Variables & constants
    "lexical_declaration",
    "variable_declaration",
    "const_item",
    "const_declaration",
    "static_item",
    // Rust-specific
    "trait_item",
    "impl_item",
    "mod_item",
    "namespace_definition",
    // Python
    "decorated_definition",
    // Go
    "type_declaration",
    // Exports
    "export_statement",
];

/// Extract the name defined by a tree-sitter definition node.
///
/// Walks standard field names (`name`, `identifier`, `declarator`) and handles
/// nested declarators and export statements.
pub(crate) fn extract_definition_name(node: tree_sitter::Node, lines: &[&str]) -> Option<String> {
    // Try standard field names
    for field in &["name", "identifier", "declarator"] {
        if let Some(child) = node.child_by_field_name(field) {
            let text = node_text_simple(child, lines);
            if !text.is_empty() {
                // For variable_declarator, get the identifier inside
                if child.kind().contains("declarator") {
                    if let Some(id) = child.child_by_field_name("name") {
                        return Some(node_text_simple(id, lines));
                    }
                }
                return Some(text);
            }
        }
    }

    // For export_statement, check the declaration child
    if node.kind() == "export_statement" {
        let mut cursor = node.walk();
        for child in node.children(&mut cursor) {
            if DEFINITION_KINDS.contains(&child.kind()) {
                return extract_definition_name(child, lines);
            }
        }
    }

    None
}

/// Get the text of a single-line node from pre-split source lines.
///
/// Returns the text slice for single-line nodes, or the text from the start
/// column to end-of-line for multi-line nodes.
pub(crate) fn node_text_simple(node: tree_sitter::Node, lines: &[&str]) -> String {
    let row = node.start_position().row;
    let col_start = node.start_position().column;
    let end_row = node.end_position().row;
    if row < lines.len() && row == end_row {
        let col_end = node.end_position().column.min(lines[row].len());
        lines[row][col_start..col_end].to_string()
    } else if row < lines.len() {
        lines[row][col_start..].to_string()
    } else {
        String::new()
    }
}

/// Extract trait name from Rust `impl Trait for Type` node.
/// Returns None for inherent impls (no trait).
pub(crate) fn extract_impl_trait(node: tree_sitter::Node, lines: &[&str]) -> Option<String> {
    let trait_node = node.child_by_field_name("trait")?;
    Some(node_text_simple(trait_node, lines))
}

/// Extract implementing type from Rust `impl ... for Type` node.
pub(crate) fn extract_impl_type(node: tree_sitter::Node, lines: &[&str]) -> Option<String> {
    let type_node = node.child_by_field_name("type")?;
    Some(node_text_simple(type_node, lines))
}

/// Extract implemented interface names from TS/Java class declaration.
/// Walks `implements_clause` (TS) and `super_interfaces` (Java) children.
pub(crate) fn extract_implemented_interfaces(
    node: tree_sitter::Node,
    lines: &[&str],
) -> Vec<String> {
    let mut interfaces = Vec::new();
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if child.kind() == "implements_clause" || child.kind() == "super_interfaces" {
            let mut inner = child.walk();
            for ident in child.children(&mut inner) {
                if ident.kind().contains("identifier") {
                    let text = node_text_simple(ident, lines);
                    if !text.is_empty() {
                        interfaces.push(text);
                    }
                }
            }
        }
    }
    interfaces
}

/// Extract parent class names from a class definition node.
///
/// Supports Python (`superclasses`), TS/JS (`class_heritage` → `extends_clause`),
/// Java (`superclass`), C++ (`base_class_clause`), and C# (`base_list`).
pub(crate) fn extract_superclasses(node: tree_sitter::Node, lines: &[&str]) -> Vec<String> {
    let mut parents = Vec::new();

    // Python: class X(Y, Z):
    // AST: class_definition → superclasses: argument_list → identifier children
    if let Some(superclasses) = node.child_by_field_name("superclasses") {
        let mut cursor = superclasses.walk();
        for child in superclasses.children(&mut cursor) {
            if child.kind().contains("identifier") {
                let text = node_text_simple(child, lines);
                if !text.is_empty() {
                    parents.push(text);
                }
            }
        }
        return parents;
    }

    // Java: class X extends Y
    // AST: class_declaration → superclass: superclass → type_identifier
    if let Some(superclass) = node.child_by_field_name("superclass") {
        let mut cursor = superclass.walk();
        for child in superclass.children(&mut cursor) {
            if child.kind().contains("identifier") {
                let text = node_text_simple(child, lines);
                if !text.is_empty() {
                    parents.push(text);
                }
            }
        }
    }

    // Walk children for TS/JS class_heritage, C++ base_class_clause, C# base_list
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            // TS/JS: class_heritage → extends_clause → value: identifier
            "class_heritage" => {
                let mut inner = child.walk();
                for heritage_child in child.children(&mut inner) {
                    if heritage_child.kind() == "extends_clause" {
                        if let Some(value) = heritage_child.child_by_field_name("value") {
                            let text = node_text_simple(value, lines);
                            if !text.is_empty() {
                                parents.push(text);
                            }
                        }
                    }
                }
            }
            // C++: base_class_clause → type_identifier (skip access_specifier)
            "base_class_clause" => {
                let mut inner = child.walk();
                for base_child in child.children(&mut inner) {
                    if base_child.kind().contains("identifier")
                        && base_child.kind() != "access_specifier"
                    {
                        let text = node_text_simple(base_child, lines);
                        if !text.is_empty() {
                            parents.push(text);
                        }
                    }
                }
            }
            // C#: base_list → identifier or generic_name children
            "base_list" => {
                let mut inner = child.walk();
                for base_child in child.children(&mut inner) {
                    if base_child.kind().contains("identifier")
                        || base_child.kind() == "generic_name"
                    {
                        let text = node_text_simple(base_child, lines);
                        if !text.is_empty() {
                            parents.push(text);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    parents
}

/// Semantic weight for definition kinds. Primary declarations rank highest.
pub(crate) fn definition_weight(kind: &str) -> u16 {
    match kind {
        "function_declaration"
        | "function_definition"
        | "function_item"
        | "method_definition"
        | "method_declaration"
        | "class_declaration"
        | "class_definition"
        | "struct_item"
        | "interface_declaration"
        | "trait_declaration"
        | "trait_item"
        | "enum_item"
        | "enum_declaration"
        | "type_item"
        | "type_declaration"
        | "decorated_definition" => 100,
        "impl_item" => 90,
        "const_item" | "const_declaration" | "static_item" => 80,
        "mod_item" | "namespace_definition" => 70,
        "lexical_declaration" | "variable_declaration" => 40,
        "export_statement" => 30,
        _ => 50,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_and_root(code: &str, lang: tree_sitter::Language) -> (tree_sitter::Tree, Vec<String>) {
        let mut parser = tree_sitter::Parser::new();
        parser.set_language(&lang).unwrap();
        let tree = parser.parse(code, None).unwrap();
        let lines: Vec<String> = code.lines().map(|s| s.to_string()).collect();
        (tree, lines)
    }

    fn find_class_node(node: tree_sitter::Node) -> Option<tree_sitter::Node> {
        if node.kind() == "class_definition"
            || node.kind() == "class_declaration"
            || node.kind() == "class_specifier"
        {
            return Some(node);
        }
        let mut cursor = node.walk();
        for child in node.children(&mut cursor) {
            if let Some(found) = find_class_node(child) {
                return Some(found);
            }
        }
        None
    }

    #[test]
    fn python_single_parent() {
        let code = "class _BaseTrainer(Trainer):\n    pass\n";
        let lang = tree_sitter_python::LANGUAGE;
        let (tree, lines) = parse_and_root(code, lang.into());
        let lines_ref: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let class_node = find_class_node(tree.root_node()).unwrap();
        let parents = extract_superclasses(class_node, &lines_ref);
        assert_eq!(parents, vec!["Trainer"]);
    }

    #[test]
    fn python_multiple_parents() {
        let code = "class DPOTrainer(_BaseTrainer, ABC):\n    pass\n";
        let lang = tree_sitter_python::LANGUAGE;
        let (tree, lines) = parse_and_root(code, lang.into());
        let lines_ref: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let class_node = find_class_node(tree.root_node()).unwrap();
        let parents = extract_superclasses(class_node, &lines_ref);
        assert_eq!(parents, vec!["_BaseTrainer", "ABC"]);
    }

    #[test]
    fn python_no_parents() {
        let code = "class Animal:\n    pass\n";
        let lang = tree_sitter_python::LANGUAGE;
        let (tree, lines) = parse_and_root(code, lang.into());
        let lines_ref: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let class_node = find_class_node(tree.root_node()).unwrap();
        let parents = extract_superclasses(class_node, &lines_ref);
        assert!(parents.is_empty());
    }

    #[test]
    fn typescript_extends() {
        let code = "class Dog extends Animal {}\n";
        let lang = tree_sitter_typescript::LANGUAGE_TYPESCRIPT;
        let (tree, lines) = parse_and_root(code, lang.into());
        let lines_ref: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let class_node = find_class_node(tree.root_node()).unwrap();
        let parents = extract_superclasses(class_node, &lines_ref);
        assert_eq!(parents, vec!["Animal"]);
    }

    #[test]
    fn java_extends() {
        let code = "class MyList extends ArrayList {}\n";
        let lang = tree_sitter_java::LANGUAGE;
        let (tree, lines) = parse_and_root(code, lang.into());
        let lines_ref: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let class_node = find_class_node(tree.root_node()).unwrap();
        let parents = extract_superclasses(class_node, &lines_ref);
        assert_eq!(parents, vec!["ArrayList"]);
    }

    #[test]
    fn cpp_base_class() {
        let code = "class Derived : public Base {};\n";
        let lang = tree_sitter_cpp::LANGUAGE;
        let (tree, lines) = parse_and_root(code, lang.into());
        let lines_ref: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        let class_node = find_class_node(tree.root_node()).unwrap();
        let parents = extract_superclasses(class_node, &lines_ref);
        assert_eq!(parents, vec!["Base"]);
    }
}
