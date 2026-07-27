import importlib.util
import copy
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "generate_bindings", ROOT / "tool" / "generate_bindings.py"
)
GENERATOR = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(GENERATOR)


class GenerateBindingsTest(unittest.TestCase):
    def setUp(self):
        self.schema = GENERATOR.load_schema()

    def test_schema_is_valid_and_generation_is_deterministic(self):
        GENERATOR.validate_schema(self.schema)
        self.assertEqual(GENERATOR.outputs(self.schema), GENERATOR.outputs(self.schema))

    def test_schema_rejects_duplicate_accessors(self):
        schema = copy.deepcopy(self.schema)
        schema["dartObjects"]["BasicBlock"]["fields"].append(
            ["int", "address"]
        )
        with self.assertRaisesRegex(ValueError, "unique Dart accessor"):
            GENERATOR.validate_schema(schema)

    def test_schema_covers_every_public_layout_and_callback(self):
        self.assertEqual(GENERATOR.audit_public_layouts(self.schema), [])

    def test_checked_in_ffi_covers_every_public_function_and_field(self):
        self.assertEqual(GENERATOR.audit_ffigen(self.schema), [])

    def test_ffi_audit_detects_function_arity_drift(self):
        self.assertEqual(
            GENERATOR._ffi_function_arity(
                "ffi.Int32 Function(ffi.Int32, ffi.Uint64)>(\n"
                "  'sogen_dart_example',\n)",
                "sogen_dart_example",
            ),
            2,
        )
        self.assertEqual(
            GENERATOR._header_function_arities(
                "SOGEN_DART_EXPORT int sogen_dart_example(int one, "
                "const char *two);"
            ),
            {"sogen_dart_example": 2},
        )

    def test_callback_ids_are_contiguous_and_metadata_is_generated(self):
        dart = GENERATOR.generated_dart(self.schema)
        header = GENERATOR.generated_header(self.schema)
        for platform, slots in self.schema["callbackSlots"].items():
            self.assertEqual([slot["id"] for slot in slots], list(range(len(slots))))
            self.assertIn(f"SOGEN_DART_{platform.upper()}_CALLBACK_COUNT", header)
            for slot in slots:
                self.assertIn(f"'{slot['field']}'", dart)
                self.assertIn(f"'{slot['type']}'", dart)
        for name in self.schema["dartObjects"]:
            self.assertIn(f"final class {name}", dart)
        for name in self.schema["objects"]:
            self.assertIn(f"typedef struct sogen_dart_{name}", header)

    def test_check_mode_is_fresh(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "generate_bindings.py"), "--check"],
            cwd=ROOT,
            check=False,
        )
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
