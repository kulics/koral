import XCTest
import Foundation

class IntegrationTests: XCTestCase {
    private func projectRootURL() -> URL? {
        let currentFileURL = URL(fileURLWithPath: #file)
        var projectRoot = currentFileURL.deletingLastPathComponent()

        while !FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("Package.swift").path) {
            if projectRoot.path == "/" {
                return nil
            }
            projectRoot = projectRoot.deletingLastPathComponent()
        }

        return projectRoot
    }

    private func runCase(named fileName: String) throws {
        guard let projectRoot = projectRootURL() else {
            XCTFail("Could not find Package.swift starting from \(#file)")
            return
        }

        let casesDir = projectRoot.appendingPathComponent("Tests/Cases")
        let file = casesDir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: file.path) else {
            XCTFail("Test case not found at \(file.path)")
            return
        }

        try runTestCase(file: file, projectRoot: projectRoot)
    }

    func test_access_modifiers() throws { try runCase(named: "access_modifiers.koral") }
    func test_bitwise() throws { try runCase(named: "bitwise.koral") }
    func test_byte_literal_coercion() throws { try runCase(named: "byte_literal_coercion.koral") }
    func test_c_keyword_escaping() throws { try runCase(named: "c_keyword_escaping.koral") }
    func test_cast_float_overflow_panic() throws { try runCase(named: "cast_float_overflow_panic.koral") }
    func test_cast_numeric() throws { try runCase(named: "cast_numeric.koral") }
    func test_cast_pointer_int_uint() throws { try runCase(named: "cast_pointer_int_uint.koral") }
    func test_cast_widening() throws { try runCase(named: "cast_widening.koral") }
    func test_comparable() throws { try runCase(named: "comparable.koral") }
    func test_comparison_pattern() throws { try runCase(named: "comparison_pattern.koral") }
    func test_compiler_method_call_compare_error() throws { try runCase(named: "compiler_method_call_compare_error.koral") }
    func test_compiler_method_call_error() throws { try runCase(named: "compiler_method_call_error.koral") }
    func test_compound_assignment() throws { try runCase(named: "compound_assignment.koral") }
    func test_conditional_pattern_matching() throws { try runCase(named: "conditional_pattern_matching.koral") }
    func test_control_flow() throws { try runCase(named: "control_flow.koral") }
    func test_deref_assignment() throws { try runCase(named: "deref_assignment.koral") }
    func test_drop_test() throws { try runCase(named: "drop_test.koral") }
    func test_expression_statement_drop() throws { try runCase(named: "expression_statement_drop.koral") }
    func test_duration_basic() throws { try runCase(named: "duration_basic.koral") }
    func test_duration_sleep() throws { try runCase(named: "duration_sleep.koral") }
    func test_duration_ffi_test() throws { try runCase(named: "duration_ffi_test.koral") }
    func test_duration_factory_methods() throws { try runCase(named: "duration_factory_methods.koral") }
    func test_diagnostic_type_mismatch_line_1() throws { try runCase(named: "diagnostic_type_mismatch_line_1.koral") }
    func test_diagnostic_type_mismatch_line_2() throws { try runCase(named: "diagnostic_type_mismatch_line_2.koral") }
    func test_diagnostic_type_mismatch_line_3() throws { try runCase(named: "diagnostic_type_mismatch_line_3.koral") }
    func test_escape_analysis() throws { try runCase(named: "escape_analysis.koral") }
    func test_escape_analysis_coverage() throws { try runCase(named: "escape_analysis_coverage.koral") }
    func test_exhaustiveness_check() throws { try runCase(named: "exhaustiveness_check.koral") }
    func test_ffi_basic() throws { try runCase(named: "ffi_basic.koral") }
    func test_ffi_foreign_body_error() throws { try runCase(named: "ffi_foreign_body_error.koral") }
    func test_ffi_foreign_generics_error() throws { try runCase(named: "ffi_foreign_generics_error.koral") }
    func test_ffi_foreign_intrinsic_conflict() throws { try runCase(named: "ffi_foreign_intrinsic_conflict.koral") }
    func test_ffi_foreign_type_body_error() throws { try runCase(named: "ffi_foreign_type_body_error.koral") }
    func test_ffi_incompatible_type() throws { try runCase(named: "ffi_incompatible_type.koral") }
    func test_ffi_foreign_global_decl() throws { try runCase(named: "ffi_foreign_global_decl.koral") }
    func test_foreign_function_duplicate_default_protected() throws { try runCase(named: "foreign_function_duplicate_default_protected.koral") }
    func test_ffi_foreign_struct_access() throws { try runCase(named: "ffi_foreign_struct_access.koral") }
    func test_ffi_opaque_ptr_required() throws { try runCase(named: "ffi_opaque_ptr_required.koral") }
    func test_ffi_pointer_member_error() throws { try runCase(named: "ffi_pointer_member_error.koral") }
    func test_float_types() throws { try runCase(named: "float_types.koral") }
    func test_for_loop_basic() throws { try runCase(named: "for_loop_basic.koral") }
    func test_for_loop_control_flow() throws { try runCase(named: "for_loop_control_flow.koral") }
    func test_for_loop_direct_iterator() throws { try runCase(named: "for_loop_direct_iterator.koral") }
    func test_for_loop_drop() throws { try runCase(named: "for_loop_drop.koral") }
    func test_for_loop_error_non_exhaustive() throws { try runCase(named: "for_loop_error_non_exhaustive.koral") }
    func test_for_loop_error_not_iterable() throws { try runCase(named: "for_loop_error_not_iterable.koral") }
    func test_for_in_requires_explicit_iterable_iterator_trait() throws { try runCase(named: "for_in_requires_explicit_iterable_iterator_trait.koral") }
    func test_for_loop_nested() throws { try runCase(named: "for_loop_nested.koral") }
    func test_functions() throws { try runCase(named: "functions.koral") }
    func test_generic_declaration_errors() throws { try runCase(named: "generic_declaration_errors.koral") }
    func test_generic_given() throws { try runCase(named: "generic_given.koral") }
    func test_generic_method_parse_test() throws { try runCase(named: "generic_method_parse_test.koral") }
    func test_generic_method_test() throws { try runCase(named: "generic_method_test.koral") }
    func test_generic_struct_validation() throws { try runCase(named: "generic_struct_validation.koral") }
    func test_generic_tostring_test() throws { try runCase(named: "generic_tostring_test.koral") }
    func test_generic_union_inference() throws { try runCase(named: "generic_union_inference.koral") }
    func test_generic_union_validation() throws { try runCase(named: "generic_union_validation.koral") }
    func test_generics() throws { try runCase(named: "generics.koral") }
    func test_hashable_basic() throws { try runCase(named: "hashable_basic.koral") }
    func test_hashable_primitives() throws { try runCase(named: "hashable_primitives.koral") }
    func test_heap_allocation() throws { try runCase(named: "heap_allocation.koral") }
    func test_hello() throws { try runCase(named: "hello.koral") }
    func test_implicit_block_value_error() throws { try runCase(named: "implicit_block_value_error.koral") }
    func test_implicit_member_expression() throws { try runCase(named: "implicit_member_expression.koral") }
    func test_integer_types() throws { try runCase(named: "integer_types.koral") }
    func test_lambda_basic() throws { try runCase(named: "lambda_basic.koral") }
    func test_lambda_closure() throws { try runCase(named: "lambda_closure.koral") }
    func test_lambda_currying() throws { try runCase(named: "lambda_currying.koral") }
    func test_lambda_error_capture_mutable() throws { try runCase(named: "lambda_error_capture_mutable.koral") }
    func test_lambda_error_inference_fail() throws { try runCase(named: "lambda_error_inference_fail.koral") }
    func test_lambda_error_type_mismatch() throws { try runCase(named: "lambda_error_type_mismatch.koral") }
    func test_lambda_higher_order() throws { try runCase(named: "lambda_higher_order.koral") }
    func test_lambda_env_drop() throws { try runCase(named: "lambda_env_drop.koral") }
    func test_lambda_parsing_test() throws { try runCase(named: "lambda_parsing_test.koral") }
    func test_lambda_type_inference() throws { try runCase(named: "lambda_type_inference.koral") }
    func test_lambda_with_generics() throws { try runCase(named: "lambda_with_generics.koral") }
    func test_let_expression() throws { try runCase(named: "let_expression.koral") }
    func test_list_test() throws { try runCase(named: "list_test.koral") }
    func test_list_sort_test() throws { try runCase(named: "list_sort_test.koral") }
    func test_deque_test() throws { try runCase(named: "deque_test.koral") }
    func test_stack_test() throws { try runCase(named: "stack_test.koral") }
    func test_queue_test() throws { try runCase(named: "queue_test.koral") }
    func test_priority_queue_test() throws { try runCase(named: "priority_queue_test.koral") }
    func test_map_test() throws { try runCase(named: "map_test.koral") }
    func test_match() throws { try runCase(named: "match.koral") }
    func test_match_drop() throws { try runCase(named: "match_drop.koral") }
    func test_math() throws { try runCase(named: "math.koral") }
    func test_missing_catchall_int() throws { try runCase(named: "missing_catchall_int.koral") }
    func test_missing_catchall_string() throws { try runCase(named: "missing_catchall_string.koral") }
    func test_monomorphization() throws { try runCase(named: "monomorphization.koral") }
    func test_never_test() throws { try runCase(named: "never_test.koral") }
    func test_newline_semicolon_blankline_blocks_dot() throws { try runCase(named: "newline_semicolon_blankline_blocks_dot.koral") }
    func test_newline_semicolon_comment_blocks_infix() throws { try runCase(named: "newline_semicolon_comment_blocks_infix.koral") }
    func test_newline_semicolon_continuation_ok() throws { try runCase(named: "newline_semicolon_continuation_ok.koral") }
    func test_non_exhaustive_bool() throws { try runCase(named: "non_exhaustive_bool.koral") }
    func test_non_exhaustive_union() throws { try runCase(named: "non_exhaustive_union.koral") }
    func test_command_basic_test() throws { try runCase(named: "command_basic_test.koral") }
    func test_command_builder_test() throws { try runCase(named: "command_builder_test.koral") }
    func test_command_pipe_test() throws { try runCase(named: "command_pipe_test.koral") }
    func test_os_basic() throws { try runCase(named: "os_basic.koral") }
    func test_os_file_info_test() throws { try runCase(named: "os_file_info_test.koral") }
    func test_os_file_test() throws { try runCase(named: "os_file_test.koral") }
    func test_os_path_test() throws { try runCase(named: "os_path_test.koral") }
    func test_os_dir_test() throws { try runCase(named: "os_dir_test.koral") }
    func test_os_fs_test() throws { try runCase(named: "os_fs_test.koral") }
    func test_os_env_test() throws { try runCase(named: "os_env_test.koral") }
    func test_option_map_test() throws { try runCase(named: "option_map_test.koral") }
    func test_pattern_combinators() throws { try runCase(named: "pattern_combinators.koral") }
    func test_duplicate_given_method() throws { try runCase(named: "duplicate_given_method.koral") }
    func test_duplicate_local_scope() throws { try runCase(named: "duplicate_local_scope.koral") }
    func test_duplicate_wildcard_let() throws { try runCase(named: "duplicate_wildcard_let.koral") }
    func test_pointer_test() throws { try runCase(named: "pointer_test.koral") }
    func test_protected_module_symbol_access_error() throws { try runCase(named: "protected_module_symbol_access_error.koral") }
    func test_range_basic() throws { try runCase(named: "range_basic.koral") }
    func test_range_iterator() throws { try runCase(named: "range_iterator.koral") }
    func test_range_unbounded() throws { try runCase(named: "range_unbounded.koral") }
    func test_recursion_check() throws { try runCase(named: "recursion_check.koral") }
    func test_recursive_union_test() throws { try runCase(named: "recursive_union_test.koral") }
    func test_indirect_recursion_error() throws { try runCase(named: "indirect_recursion_error.koral") }
    func test_indirect_recursion_chain_error() throws { try runCase(named: "indirect_recursion_chain_error.koral") }
    func test_indirect_recursion_ref_ok() throws { try runCase(named: "indirect_recursion_ref_ok.koral") }
    func test_inter_procedural_escape() throws { try runCase(named: "inter_procedural_escape.koral") }
    func test_inter_procedural_escape_recursive_ref_regression() throws { try runCase(named: "inter_procedural_escape_recursive_ref_regression.koral") }
    func test_generic_recursion_error() throws { try runCase(named: "generic_recursion_error.koral") }
    func test_ref_method_call() throws { try runCase(named: "ref_method_call.koral") }
    func test_ref_escape_pattern_alias() throws { try runCase(named: "ref_escape_pattern_alias.koral") }
    func test_result_map_test() throws { try runCase(named: "result_map_test.koral") }
    func test_result_void_test() throws { try runCase(named: "result_void_test.koral") }
    func test_return_break_continue() throws { try runCase(named: "return_break_continue.koral") }
    func test_rune_basic() throws { try runCase(named: "rune_basic.koral") }
    func test_rune_literal() throws { try runCase(named: "rune_literal.koral") }
    func test_rune_string() throws { try runCase(named: "rune_string.koral") }
    func test_rvalue_ref_param_error() throws { try runCase(named: "rvalue_ref_param_error.koral") }
    func test_rvalue_temp_materialization() throws { try runCase(named: "rvalue_temp_materialization.koral") }
    func test_set_test() throws { try runCase(named: "set_test.koral") }
    func test_single_quote_string() throws { try runCase(named: "single_quote_string.koral") }
    func test_stream_api_test() throws { try runCase(named: "stream_api_test.koral") }
    func test_stream_basic() throws { try runCase(named: "stream_basic.koral") }
    func test_stream_inference_test() throws { try runCase(named: "stream_inference_test.koral") }
    func test_stream_simple() throws { try runCase(named: "stream_simple.koral") }
    func test_stream_sum_product_average() throws { try runCase(named: "stream_sum_product_average.koral") }
    func test_string() throws { try runCase(named: "string.koral") }
    func test_string_methods() throws { try runCase(named: "string_methods.koral") }
    func test_string_literal_borrow_cow() throws { try runCase(named: "string_literal_borrow_cow.koral") }
    func test_string_literal_borrow_edges() throws { try runCase(named: "string_literal_borrow_edges.koral") }
    func test_string_interpolation() throws { try runCase(named: "string_interpolation.koral") }
    func test_string_interpolation_drop() throws { try runCase(named: "string_interpolation_drop.koral") }
    func test_string_interpolation_error_empty() throws { try runCase(named: "string_interpolation_error_empty.koral") }
    func test_string_interpolation_error_unterminated() throws { try runCase(named: "string_interpolation_error_unterminated.koral") }
    func test_string_interpolation_requires_explicit_tostring_trait() throws { try runCase(named: "string_interpolation_requires_explicit_tostring_trait.koral") }
    func test_struct_with_ref() throws { try runCase(named: "struct_with_ref.koral") }
    func test_structs() throws { try runCase(named: "structs.koral") }
    func test_subscript_test() throws { try runCase(named: "subscript_test.koral") }
    func test_subscript_requires_explicit_trait() throws { try runCase(named: "subscript_requires_explicit_trait.koral") }
    func test_closure_variable_drop() throws { try runCase(named: "closure_variable_drop.koral") }
    func test_if_pattern_drop() throws { try runCase(named: "if_pattern_drop.koral") }
    func test_while_pattern_drop() throws { try runCase(named: "while_pattern_drop.koral") }
    func test_chain_call_drop() throws { try runCase(named: "chain_call_drop.koral") }
    func test_trait_cannot_as_type() throws { try runCase(named: "trait_cannot_as_type.koral") }
    func test_trait_constraint_validation() throws { try runCase(named: "trait_constraint_validation.koral") }
    func test_empty_given_trait_impl_error() throws { try runCase(named: "empty_given_trait_impl_error.koral") }
    func test_given_and_given_trait_coexist() throws { try runCase(named: "given_and_given_trait_coexist.koral") }
    func test_trait_equatable() throws { try runCase(named: "trait_equatable.koral") }
    func test_trait_entity_merge_basic() throws { try runCase(named: "trait_entity_merge_basic.koral") }
    func test_trait_entity_qualified_call() throws { try runCase(named: "trait_entity_qualified_call.koral") }
    func test_trait_entity_generic_bound() throws { try runCase(named: "trait_entity_generic_bound.koral") }
    func test_trait_entity_given_type_trait_type_root() throws { try runCase(named: "trait_entity_given_type_trait_type_root.koral") }
    func test_trait_entity_generic_trait() throws { try runCase(named: "trait_entity_generic_trait.koral") }
    func test_trait_entity_generic_type_trait() throws { try runCase(named: "trait_entity_generic_type_trait.koral") }
    func test_trait_generic_method_test() throws { try runCase(named: "trait_generic_method_test.koral") }
    func test_trait_inheritance() throws { try runCase(named: "trait_inheritance.koral") }
    func test_trait_inheritance_multiple() throws { try runCase(named: "trait_inheritance_multiple.koral") }
    func test_trait_inheritance_requires_parent_given_error() throws { try runCase(named: "trait_inheritance_requires_parent_given_error.koral") }
    func test_trait_inheritance_validation() throws { try runCase(named: "trait_inheritance_validation.koral") }
    func test_trait_constraint_cache_collision_error() throws { try runCase(named: "trait_constraint_cache_collision_error.koral") }
    func test_operator_requires_explicit_trait() throws { try runCase(named: "operator_requires_explicit_trait.koral") }
    func test_mul_operator_requires_explicit_trait() throws { try runCase(named: "mul_operator_requires_explicit_trait.koral") }
    func test_equality_operator_requires_explicit_trait() throws { try runCase(named: "equality_operator_requires_explicit_trait.koral") }
    func test_comparison_operator_requires_explicit_trait() throws { try runCase(named: "comparison_operator_requires_explicit_trait.koral") }
    func test_trait_missing_method_error() throws { try runCase(named: "trait_missing_method_error.koral") }
    func test_union_construction() throws { try runCase(named: "union_construction.koral") }
    func test_union_methods() throws { try runCase(named: "union_methods.koral") }
    func test_union_parsing() throws { try runCase(named: "union_parsing.koral") }
    func test_unreachable_pattern() throws { try runCase(named: "unreachable_pattern.koral") }
    func test_value_param_copy() throws { try runCase(named: "value_param_copy.koral") }
    func test_zip_test() throws { try runCase(named: "zip_test.koral") }
    func test_yield_not_last_error() throws { try runCase(named: "yield_not_last_error.koral") }
    func test_yield_basic() throws { try runCase(named: "yield_basic.koral") }
    func test_yield_errors() throws { try runCase(named: "yield_errors.koral") }
    func test_or_else_early_exit() throws { try runCase(named: "or_else_early_exit.koral") }
    func test_and_then_flatten() throws { try runCase(named: "and_then_flatten.koral") }
    func test_or_else_and_then_error() throws { try runCase(named: "or_else_and_then_error.koral") }
    func test_or_else_and_then_precedence() throws { try runCase(named: "or_else_and_then_precedence.koral") }
    func test_or_else_and_then_drop() throws { try runCase(named: "or_else_and_then_drop.koral") }
    func test_type_alias_basic() throws { try runCase(named: "type_alias_basic.koral") }
    func test_type_alias_error_cycle() throws { try runCase(named: "type_alias_error_cycle.koral") }
    func test_type_alias_error_undefined() throws { try runCase(named: "type_alias_error_undefined.koral") }
    func test_type_alias_error_duplicate() throws { try runCase(named: "type_alias_error_duplicate.koral") }
    func test_type_alias_error_lowercase() throws { try runCase(named: "type_alias_error_lowercase.koral") }
    func test_struct_destructuring() throws { try runCase(named: "struct_destructuring.koral") }
    func test_struct_destructuring_generic() throws { try runCase(named: "struct_destructuring_generic.koral") }
    func test_struct_visibility_test() throws { try runCase(named: "struct_visibility_test/struct_visibility_test.koral") }
    func test_struct_visibility_member_test() throws { try runCase(named: "struct_visibility_member_test/struct_visibility_member_test.koral") }
    func test_struct_visibility_wildcard_test() throws { try runCase(named: "struct_visibility_wildcard_test/struct_visibility_wildcard_test.koral") }
    func test_private_using_file_scope_test() throws { try runCase(named: "private_using_file_scope_test/private_using_file_scope_test.koral") }
    func test_using_file_merge_path_error() throws { try runCase(named: "using_file_merge_path_error.koral") }
    func test_parent_trait_requires_using() throws { try runCase(named: "module_error_tests/parent_trait_requires_using_test/parent_trait_requires_using_test.koral") }
    func test_using_self_requires_item() throws { try runCase(named: "using_self_requires_item.koral") }
    func test_receiver_self_syntax_error() throws { try runCase(named: "receiver_self_syntax_error.koral") }
    func test_using_super_requires_item() throws { try runCase(named: "using_super_requires_item.koral") }
    func test_module_symbol_requires_explicit_import() throws { try runCase(named: "module_import_rules_test/module_import_rules_test.koral") }
    func test_using_batch_does_not_import_submodules() throws { try runCase(named: "using_batch_no_submodule_import_test/using_batch_no_submodule_import_test.koral") }
    func test_module_qualified_type_valid() throws { try runCase(named: "module_qualified_type_valid_test/module_qualified_type_valid_test.koral") }
    func test_module_qualified_type_owner_error() throws { try runCase(named: "module_qualified_type_owner_error_test/module_qualified_type_owner_error_test.koral") }
    func test_module_qualified_generic_type_owner_error() throws { try runCase(named: "module_qualified_generic_type_owner_error_test/module_qualified_generic_type_owner_error_test.koral") }
    func test_numeric_literal_bases() throws { try runCase(named: "numeric_literal_bases.koral") }
    func test_numeric_literal_bases_error_binary_digit() throws { try runCase(named: "numeric_literal_bases_error_binary_digit.koral") }
    func test_numeric_literal_bases_error_octal_digit() throws { try runCase(named: "numeric_literal_bases_error_octal_digit.koral") }
    func test_numeric_literal_bases_error_empty_binary() throws { try runCase(named: "numeric_literal_bases_error_empty_binary.koral") }
    func test_numeric_literal_bases_error_float() throws { try runCase(named: "numeric_literal_bases_error_float.koral") }
    func test_checked_arithmetic() throws { try runCase(named: "checked_arithmetic.koral") }
    func test_checked_overflow_add() throws { try runCase(named: "checked_overflow_add.koral") }
    func test_checked_overflow_sub() throws { try runCase(named: "checked_overflow_sub.koral") }
    func test_checked_overflow_mul() throws { try runCase(named: "checked_overflow_mul.koral") }
    func test_checked_div_zero() throws { try runCase(named: "checked_div_zero.koral") }
    func test_checked_div_min() throws { try runCase(named: "checked_div_min.koral") }
    func test_checked_shift_invalid() throws { try runCase(named: "checked_shift_invalid.koral") }
    func test_trait_object_basic() throws { try runCase(named: "trait_object_basic.koral") }
    func test_trait_object_error() throws { try runCase(named: "trait_object_error.koral") }
    func test_trait_object_safety_error() throws { try runCase(named: "trait_object_safety_error.koral") }
    func test_trait_object_deref_error() throws { try runCase(named: "trait_object_deref_error.koral") }
    func test_trait_object_self_conformance() throws { try runCase(named: "trait_object_self_conformance.koral") }
    func test_trait_object_weakref() throws { try runCase(named: "trait_object_weakref.koral") }
    func test_trait_object_refcount_regression() throws { try runCase(named: "trait_object_refcount_regression.koral") }
    func test_mono_time_test() throws { try runCase(named: "mono_time_test.koral") }
    func test_timezone_test() throws { try runCase(named: "timezone_test.koral") }
    func test_datetime_basic() throws { try runCase(named: "datetime_basic.koral") }
    func test_datetime_ops() throws { try runCase(named: "datetime_ops.koral") }
    func test_datetime_iso8601() throws { try runCase(named: "datetime_iso8601.koral") }
    func test_datetime_requires_import() throws { try runCase(named: "datetime_requires_import.koral") }
    func test_std_math_float_test() throws { try runCase(named: "std_math_float_test.koral") }
    func test_std_math_int_test() throws { try runCase(named: "std_math_int_test.koral") }
    func test_random_xoshiro_test() throws { try runCase(named: "random_xoshiro_test.koral") }
    func test_random_zero_seed_panic() throws { try runCase(named: "random_zero_seed_panic.koral") }
    func test_random_empty_range_panic() throws { try runCase(named: "random_empty_range_panic.koral") }
    func test_random_api_test() throws { try runCase(named: "random_api_test.koral") }
    func test_random_nominal_regression() throws { try runCase(named: "random_nominal_regression.koral") }
    func test_convert_parse_int_test() throws { try runCase(named: "convert_parse_int_test.koral") }
    func test_convert_parse_float_test() throws { try runCase(named: "convert_parse_float_test.koral") }
    func test_convert_format_int_test() throws { try runCase(named: "convert_format_int_test.koral") }
    func test_convert_format_float_test() throws { try runCase(named: "convert_format_float_test.koral") }
    func test_regex_basic_test() throws { try runCase(named: "regex_basic_test.koral") }
    func test_io_buffer_test() throws { try runCase(named: "io_buffer_test.koral") }
    func test_io_error_test() throws { try runCase(named: "io_error_test.koral") }
    func test_io_buf_reader_test() throws { try runCase(named: "io_buf_reader_test.koral") }
    func test_io_buf_writer_test() throws { try runCase(named: "io_buf_writer_test.koral") }
    func test_io_utils_test() throws { try runCase(named: "io_utils_test.koral") }
    func test_io_utils_checkpoint() throws { try runCase(named: "io_utils_checkpoint.koral") }
    func test_sync_thread_test() throws { try runCase(named: "sync_thread_test.koral") }
    func test_sync_mutex_test() throws { try runCase(named: "sync_mutex_test.koral") }
    func test_sync_shared_mutex_test() throws { try runCase(named: "sync_shared_mutex_test.koral") }
    func test_sync_channel_test() throws { try runCase(named: "sync_channel_test.koral") }
    func test_sync_misc_test() throws { try runCase(named: "sync_misc_test.koral") }
    func test_defer_basic() throws { try runCase(named: "defer_basic.koral") }
    func test_defer_control_flow() throws { try runCase(named: "defer_control_flow.koral") }
    func test_defer_scope() throws { try runCase(named: "defer_scope.koral") }
    func test_defer_error() throws { try runCase(named: "defer_error.koral") }
    func test_net_ip_addr_test() throws { try runCase(named: "net_ip_addr_test.koral") }
    func test_net_socket_addr_test() throws { try runCase(named: "net_socket_addr_test.koral") }
    func test_net_tcp_test() throws { try runCase(named: "net_tcp_test.koral") }
    func test_net_udp_test() throws { try runCase(named: "net_udp_test.koral") }
    
    func runTestCase(file: URL, projectRoot: URL) throws {
        // 1. Parse expectations
        let content = try String(contentsOf: file, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var expectedOutput: [String] = []
        var expectedErrors: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "// EXPECT: ") {
                let expectation = String(trimmed.dropFirst("// EXPECT: ".count))
                expectedOutput.append(expectation)
            } else if trimmed.starts(with: "// EXPECT-ERROR: ") {
                let expectation = String(trimmed.dropFirst("// EXPECT-ERROR: ".count))
                expectedErrors.append(expectation)
            }
        }
        
        // 2. Prepare output and cleanup
        // Use an isolated directory under CasesOutput, then clean it up after each run.
        let baseName = file.deletingPathExtension().lastPathComponent
        let casesOutputRoot = projectRoot.appendingPathComponent("Tests/CasesOutput")
        let runDir = casesOutputRoot.appendingPathComponent(baseName).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true, attributes: nil)
        let outputDir = runDir
        
        defer {
            try? FileManager.default.removeItem(at: runDir)
        }

        // 3. Run compiler
        // We use the built binary directly to avoid swift run lock
        var koralcBinary = projectRoot.appendingPathComponent(".build/debug/koralc")
        #if os(Windows)
        koralcBinary.appendPathExtension("exe")
        #endif
        
        guard FileManager.default.fileExists(atPath: koralcBinary.path) else {
            XCTFail("koralc binary not found at \(koralcBinary.path). Please build first.")
            return
        }
        
        let process = Process()
        process.executableURL = koralcBinary
        process.arguments = ["run", file.path, "-o", outputDir.path]
        process.currentDirectoryURL = projectRoot
        
        // Use temporary files instead of pipes to avoid buffer deadlock
        let tempDir = FileManager.default.temporaryDirectory
        let stdoutFile = tempDir.appendingPathComponent(UUID().uuidString + "_stdout.txt")
        let stderrFile = tempDir.appendingPathComponent(UUID().uuidString + "_stderr.txt")
        
        _ = FileManager.default.createFile(atPath: stdoutFile.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderrFile.path, contents: nil)
        
        defer {
            try? FileManager.default.removeItem(at: stdoutFile)
            try? FileManager.default.removeItem(at: stderrFile)
        }
        
        let stdoutHandle = try FileHandle(forWritingTo: stdoutFile)
        let stderrHandle = try FileHandle(forWritingTo: stderrFile)
        
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        
        try process.run()
        process.waitUntilExit()
        
        try? stdoutHandle.close()
        try? stderrHandle.close()
        
        // Read captured output from temp files
        let stdoutData = (try? Data(contentsOf: stdoutFile)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrFile)) ?? Data()
        let combinedData = stdoutData + stderrData
        
        // Use a lossy UTF-8 decode so one bad byte doesn't drop all output.
        var output = String(decoding: combinedData, as: UTF8.self)
        
        // Normalize line endings to \n
        output = output.replacingOccurrences(of: "\r\n", with: "\n")
        output = output.replacingOccurrences(of: "\r", with: "\n")
        
        // 4. Verify output (Robust Line Matching)
        let outputLines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var currentLineIndex = 0

        // Negative tests: expect compilation/runtime failure and specific error text.
        if !expectedErrors.isEmpty {
            if process.terminationStatus == 0 {
                XCTFail("""
                Test failed: \(file.lastPathComponent)
                Expected non-zero exit code, got 0.

                Actual Output Lines:
                \(outputLines.joined(separator: "\n"))
                """)
                return
            }

            for expected in expectedErrors {
                let cleanExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanExpected.isEmpty { continue }

                var found = false
                for i in currentLineIndex..<outputLines.count {
                    if outputLines[i].contains(cleanExpected) {
                        found = true
                        currentLineIndex = i + 1
                        break
                    }
                }

                if !found {
                    XCTFail("""
                    Test failed: \(file.lastPathComponent)
                    Missing expected error: "\(cleanExpected)"

                    Scanned from line \(currentLineIndex)

                    Actual Output Lines:
                    \(outputLines.joined(separator: "\n"))
                    """)
                    return
                }
            }
            return
        }
        
        for expected in expectedOutput {
             let cleanExpected = expected.trimmingCharacters(in: .whitespacesAndNewlines)
             if cleanExpected.isEmpty { continue }

            var found = false
            // Scan forward from current position
            for i in currentLineIndex..<outputLines.count {
                if outputLines[i].contains(cleanExpected) {
                    found = true
                    currentLineIndex = i + 1 // Advance to next line for next expectation
                    break
                }
            }
            
            if !found {
                XCTFail("""
                Test failed: \(file.lastPathComponent)
                Missing expected output: "\(cleanExpected)"
                
                Scanned from line \(currentLineIndex)
                
                Actual Output Lines:
                \(outputLines.joined(separator: "\n"))
                """)
                return
            }
        }
        
        // Check exit code if needed (default expects 0 unless specified otherwise)
        // For now, we assume success if output matches.
        // Note: Our current compiler might return non-zero for valid programs (e.g. returning result of calculation)
        // So we don't strictly check process.terminationStatus == 0 yet, unless we add // EXIT: 0
    }
}
