"""Generate and statically validate reusable CustomNode Python source."""

from __future__ import annotations

import ast
import hashlib
import keyword
import re
from dataclasses import dataclass, field
from typing import Any, Literal

from nmtk_sdk.safety import scan_imports

from neurocnl.training.dag_schema import PIPELINE_NODE_TYPES

from ...contracts.design_contracts import ComponentBlock, ParameterDef, PortDef

SUPPORTED_CANVASES = frozenset({"model", "training", "eval", "inference"})
SUPPORTED_FRAMEWORKS = frozenset(
    {"nengo", "norse", "spikingjelley", "brian2", "snntorch_sim"}
)
SUPPORTED_PARAMETER_TYPES = frozenset({"float", "int", "bool", "enum", "text"})


@dataclass(frozen=True)
class SourceDiagnostic:
    """A source-level validation issue suitable for an editor."""

    message: str
    severity: Literal["error", "warning"] = "error"
    line: int = 1
    column: int = 1
    end_line: int | None = None
    end_column: int | None = None
    code: str = "custom-node"


@dataclass
class SourceAnalysis:
    """Static information extracted from one CustomNode subclass."""

    diagnostics: list[SourceDiagnostic] = field(default_factory=list)
    class_name: str | None = None
    name: str | None = None
    category: str | None = None
    author: str = ""
    version: str = "1.0.0"
    node_id: str | None = None
    base_component_id: str | None = None
    base_nir_type: str | None = None
    base_pipeline_type: str | None = None
    canvases: list[str] = field(default_factory=list)
    frameworks: list[str] = field(default_factory=list)
    parameters: list[ParameterDef] = field(default_factory=list)
    ports: list[PortDef] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        return not any(item.severity == "error" for item in self.diagnostics)

    def to_component(self, *, source_filename: str | None = None) -> ComponentBlock:
        """Build component metadata after successful validation."""
        if not self.valid or not self.name or not self.category:
            raise ValueError("Cannot build component metadata from invalid source")
        component_id = self.node_id or "custom_unsaved_preview"
        return ComponentBlock(
            id=component_id,
            name=self.name,
            category=self.category,
            description="",
            icon="custom_node",
            parameters=self.parameters,
            ports=self.ports,
            cnl_template="",
            is_custom=True,
            canvas_contexts=self.canvases,
            supported_frameworks=self.frameworks,
            author=self.author,
            version=self.version,
            source_filename=source_filename,
            source_available=source_filename is not None,
            base_component_id=self.base_component_id,
            base_nir_type=self.base_nir_type,
            base_pipeline_type=self.base_pipeline_type,
        )


def source_revision(source: str) -> str:
    """Return an opaque revision used for optimistic concurrency."""
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def _python_identifier(value: str, *, prefix: str) -> str:
    candidate = re.sub(r"\W+", "_", value).strip("_")
    if not candidate:
        candidate = prefix
    if candidate[0].isdigit() or keyword.iskeyword(candidate):
        candidate = f"{prefix}_{candidate}"
    return candidate


def _class_name(display_name: str) -> str:
    words = re.findall(r"[A-Za-z0-9]+", display_name)
    value = "".join(word[:1].upper() + word[1:] for word in words) or "CustomNode"
    if value[0].isdigit():
        value = f"Node{value}"
    return value


def _literal(value: Any) -> str:
    return repr(value)


def generate_custom_node_source(
    *,
    component: ComponentBlock | None,
    component_id: str,
    nir_type: str | None,
    display_name: str,
    category: str,
    parameters: dict[str, Any],
    parameter_definitions: list[ParameterDef],
    ports: list[PortDef],
    pipeline_type: str | None = None,
    canvas_context: str | None = None,
) -> str:
    """Generate an editable CustomNode class for a selected built-in node."""
    definitions = (
        parameter_definitions
        if (nir_type is not None or pipeline_type is not None) and parameter_definitions
        else component.parameters if component is not None else parameter_definitions
    )
    resolved_ports = (
        ports
        if (nir_type is not None or pipeline_type is not None) and ports
        else component.ports if component is not None else ports
    )
    resolved_name = display_name or (
        component.name if component is not None else component_id
    )
    resolved_category = (
        category
        if pipeline_type is not None
        else component.category if component else category
    )
    frameworks = (
        ["snntorch_sim"]
        if pipeline_type is not None
        else (
            component.supported_frameworks
            if component is not None and component.supported_frameworks
            else ["nengo"]
        )
    )
    canvases = (
        [canvas_context]
        if pipeline_type is not None and canvas_context is not None
        else (
            component.canvas_contexts
            if component is not None and component.canvas_contexts
            else ["model"]
        )
    )

    lines = [
        "from nmtk_sdk import CustomNode, param, port",
        "",
        "",
        f"class {_class_name(resolved_name)}(CustomNode):",
        f"    name = {_literal(resolved_name)}",
        f"    category = {_literal(resolved_category or 'custom')}",
        f"    canvases = {_literal(list(canvases))}",
        f"    frameworks = {_literal(list(frameworks))}",
        f"    description = {_literal(component.description if component else '')}",
        '    author = ""',
        '    version = "1.0.0"',
    ]
    if pipeline_type:
        lines.append(f"    base_pipeline_type = {_literal(pipeline_type)}")
    elif nir_type:
        lines.append(f"    base_nir_type = {_literal(nir_type)}")
    elif component_id:
        lines.append(f"    base_component_id = {_literal(component_id)}")

    for definition in definitions:
        current = parameters.get(definition.name, definition.default)
        kwargs = [
            f"type={_literal(definition.type)}",
            f"default={_literal(current)}",
            f"label={_literal(definition.label)}",
        ]
        if definition.description:
            kwargs.append(f"description={_literal(definition.description)}")
        if definition.unit:
            kwargs.append(f"unit={_literal(definition.unit)}")
        if definition.min is not None:
            kwargs.append(f"min={_literal(definition.min)}")
        if definition.max is not None:
            kwargs.append(f"max={_literal(definition.max)}")
        if definition.enum_values:
            kwargs.append(f"enum_values={_literal(definition.enum_values)}")
        method_name = _python_identifier(definition.name, prefix="parameter")
        lines.extend(
            [
                "",
                f"    @param({', '.join(kwargs)})",
                f"    def {method_name}(self): ...",
            ]
        )

    for port_definition in resolved_ports:
        method_name = _python_identifier(port_definition.id, prefix="port")
        lines.extend(
            [
                "",
                "    @port("
                f"id={_literal(port_definition.id)}, "
                f"direction={_literal(port_definition.direction)}, "
                f"label={_literal(port_definition.label)})",
                f"    def {method_name}(self): ...",
            ]
        )

    implementation_hint = (
        [
            "",
            "    # Optional: override this to replace the built-in notebook snippet.",
            "    # def to_pipeline(self, params):",
            '    #     return "# Python emitted into the training/evaluation cell"',
        ]
        if pipeline_type is not None
        else [
            "",
            "    # Optional: override to_nengo/to_norse/etc. to replace the",
            "    # delegated built-in behavior with a custom implementation.",
        ]
    )
    lines.extend([*implementation_hint, ""])
    return "\n".join(lines)


def _literal_assignment(
    class_node: ast.ClassDef,
    name: str,
    diagnostics: list[SourceDiagnostic],
    *,
    required: bool = False,
) -> Any:
    for statement in class_node.body:
        if isinstance(statement, ast.Assign | ast.AnnAssign) and (
            (
                isinstance(statement, ast.Assign)
                and any(
                    isinstance(target, ast.Name) and target.id == name
                    for target in statement.targets
                )
            )
            or (
                isinstance(statement, ast.AnnAssign)
                and isinstance(statement.target, ast.Name)
                and statement.target.id == name
            )
        ):
            value_node = statement.value
            if value_node is None:
                break
            try:
                return ast.literal_eval(value_node)
            except (ValueError, TypeError):
                diagnostics.append(
                    SourceDiagnostic(
                        message=f"{name} must be a literal value.",
                        line=statement.lineno,
                        column=statement.col_offset + 1,
                        code="literal-required",
                    )
                )
                return None
    if required:
        diagnostics.append(
            SourceDiagnostic(
                message=f"CustomNode must declare {name}.",
                line=class_node.lineno,
                column=class_node.col_offset + 1,
                code="missing-metadata",
            )
        )
    return None


def _decorator_values(
    decorator: ast.expr,
    expected_name: str,
    diagnostics: list[SourceDiagnostic],
) -> dict[str, Any] | None:
    if not isinstance(decorator, ast.Call):
        return None
    function = decorator.func
    if not isinstance(function, ast.Name) or function.id != expected_name:
        return None
    values: dict[str, Any] = {}
    for argument in decorator.keywords:
        if argument.arg is None:
            diagnostics.append(
                SourceDiagnostic(
                    message=f"@{expected_name} does not accept **kwargs expansion.",
                    line=decorator.lineno,
                    column=decorator.col_offset + 1,
                    code="literal-required",
                )
            )
            continue
        try:
            values[argument.arg] = ast.literal_eval(argument.value)
        except (ValueError, TypeError):
            diagnostics.append(
                SourceDiagnostic(
                    message=f"@{expected_name} argument '{argument.arg}' must be literal.",
                    line=argument.value.lineno,
                    column=argument.value.col_offset + 1,
                    code="literal-required",
                )
            )
    return values


def analyze_custom_node_source(
    source: str,
    *,
    known_component_ids: set[str] | None = None,
) -> SourceAnalysis:
    """Validate syntax and the statically declared nmtk_sdk contract."""
    result = SourceAnalysis()
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        result.diagnostics.append(
            SourceDiagnostic(
                message=exc.msg,
                line=exc.lineno or 1,
                column=exc.offset or 1,
                end_line=exc.end_lineno,
                end_column=exc.end_offset,
                code="python-syntax",
            )
        )
        return result

    for module in sorted(set(scan_imports(source))):
        result.diagnostics.append(
            SourceDiagnostic(
                message=f"Importing '{module}' is not allowed in custom nodes.",
                code="unsafe-import",
            )
        )

    custom_classes = [
        node
        for node in tree.body
        if isinstance(node, ast.ClassDef)
        and any(
            isinstance(base, ast.Name) and base.id == "CustomNode"
            for base in node.bases
        )
    ]
    if len(custom_classes) != 1:
        result.diagnostics.append(
            SourceDiagnostic(
                message="Source must contain exactly one CustomNode subclass.",
                code="custom-node-count",
            )
        )
        return result

    class_node = custom_classes[0]
    result.class_name = class_node.name
    result.name = _literal_assignment(
        class_node, "name", result.diagnostics, required=True
    )
    result.category = _literal_assignment(
        class_node, "category", result.diagnostics, required=True
    )
    result.author = _literal_assignment(class_node, "author", result.diagnostics) or ""
    result.version = (
        _literal_assignment(class_node, "version", result.diagnostics) or "1.0.0"
    )
    result.node_id = _literal_assignment(class_node, "node_id", result.diagnostics)
    result.base_component_id = _literal_assignment(
        class_node, "base_component_id", result.diagnostics
    )
    result.base_nir_type = _literal_assignment(
        class_node, "base_nir_type", result.diagnostics
    )
    result.base_pipeline_type = _literal_assignment(
        class_node, "base_pipeline_type", result.diagnostics
    )
    result.canvases = (
        _literal_assignment(class_node, "canvases", result.diagnostics, required=True)
        or []
    )
    result.frameworks = (
        _literal_assignment(class_node, "frameworks", result.diagnostics, required=True)
        or []
    )

    if not isinstance(result.name, str) or not result.name.strip():
        result.diagnostics.append(
            SourceDiagnostic(
                message="name must be a non-empty string.", code="invalid-name"
            )
        )
    if not isinstance(result.category, str) or not result.category.strip():
        result.diagnostics.append(
            SourceDiagnostic(
                message="category must be a non-empty string.", code="invalid-category"
            )
        )
    if not isinstance(result.canvases, list) or not all(
        isinstance(value, str) for value in result.canvases
    ):
        result.diagnostics.append(
            SourceDiagnostic(
                message="canvases must be a list of strings.", code="invalid-canvases"
            )
        )
        result.canvases = []
    else:
        unknown = sorted(set(result.canvases) - SUPPORTED_CANVASES)
        if unknown:
            result.diagnostics.append(
                SourceDiagnostic(
                    message=f"Unsupported canvas values: {', '.join(unknown)}.",
                    code="invalid-canvases",
                )
            )
    if not isinstance(result.frameworks, list) or not all(
        isinstance(value, str) for value in result.frameworks
    ):
        result.diagnostics.append(
            SourceDiagnostic(
                message="frameworks must be a list of strings.",
                code="invalid-frameworks",
            )
        )
        result.frameworks = []
    else:
        unknown = sorted(set(result.frameworks) - SUPPORTED_FRAMEWORKS)
        if unknown:
            result.diagnostics.append(
                SourceDiagnostic(
                    message=f"Unsupported framework values: {', '.join(unknown)}.",
                    code="invalid-frameworks",
                )
            )

    if result.node_id is not None and (
        not isinstance(result.node_id, str)
        or re.fullmatch(r"custom_[a-z0-9_]+", result.node_id) is None
    ):
        result.diagnostics.append(
            SourceDiagnostic(
                message=(
                    "node_id must start with 'custom_' and contain only lowercase "
                    "letters, numbers, and underscores."
                ),
                code="invalid-node-id",
            )
        )
    if (
        result.base_component_id
        and known_component_ids is not None
        and result.base_component_id not in known_component_ids
    ):
        result.diagnostics.append(
            SourceDiagnostic(
                message=f"Unknown base component '{result.base_component_id}'.",
                code="unknown-base-component",
            )
        )
    if result.base_nir_type is not None and (
        not isinstance(result.base_nir_type, str)
        or not result.base_nir_type.startswith("nir.")
    ):
        result.diagnostics.append(
            SourceDiagnostic(
                message="base_nir_type must be a 'nir.*' identifier.",
                code="invalid-base-nir-type",
            )
        )
    if result.base_pipeline_type is not None and (
        not isinstance(result.base_pipeline_type, str)
        or result.base_pipeline_type not in PIPELINE_NODE_TYPES
    ):
        result.diagnostics.append(
            SourceDiagnostic(
                message=f"Unknown base pipeline type '{result.base_pipeline_type}'.",
                code="invalid-base-pipeline-type",
            )
        )

    declared_bases = [
        value
        for value in (
            result.base_component_id,
            result.base_nir_type,
            result.base_pipeline_type,
        )
        if value is not None
    ]
    if len(declared_bases) > 1:
        result.diagnostics.append(
            SourceDiagnostic(
                message="Declare only one base component, NIR type, or pipeline type.",
                code="multiple-base-types",
            )
        )

    parameter_names: set[str] = set()
    port_ids: set[str] = set()
    method_names = {
        statement.name
        for statement in class_node.body
        if isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef)
    }
    for statement in class_node.body:
        if not isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
            continue
        for decorator in statement.decorator_list:
            values = _decorator_values(decorator, "param", result.diagnostics)
            if values is not None:
                parameter_name = statement.name
                parameter_type = values.get("type")
                if parameter_name in parameter_names:
                    result.diagnostics.append(
                        SourceDiagnostic(
                            message=f"Duplicate parameter '{parameter_name}'.",
                            line=statement.lineno,
                            column=statement.col_offset + 1,
                            code="duplicate-parameter",
                        )
                    )
                    continue
                parameter_names.add(parameter_name)
                if parameter_type not in SUPPORTED_PARAMETER_TYPES:
                    result.diagnostics.append(
                        SourceDiagnostic(
                            message=f"Unsupported parameter type '{parameter_type}'.",
                            line=statement.lineno,
                            column=statement.col_offset + 1,
                            code="invalid-parameter",
                        )
                    )
                    continue
                if "default" not in values:
                    result.diagnostics.append(
                        SourceDiagnostic(
                            message=f"Parameter '{parameter_name}' needs a default value.",
                            line=statement.lineno,
                            column=statement.col_offset + 1,
                            code="invalid-parameter",
                        )
                    )
                    continue
                default_value = values["default"]
                valid_default = (
                    default_value is None
                    or (parameter_type == "bool" and isinstance(default_value, bool))
                    or (
                        parameter_type == "int"
                        and isinstance(default_value, int)
                        and not isinstance(default_value, bool)
                    )
                    or (
                        parameter_type == "float"
                        and isinstance(default_value, int | float)
                        and not isinstance(default_value, bool)
                    )
                    or (
                        parameter_type in {"enum", "text"}
                        and isinstance(default_value, str)
                    )
                )
                if not valid_default:
                    result.diagnostics.append(
                        SourceDiagnostic(
                            message=(
                                f"Parameter '{parameter_name}' has a default "
                                f"incompatible with type '{parameter_type}'."
                            ),
                            line=statement.lineno,
                            column=statement.col_offset + 1,
                            code="invalid-parameter-default",
                        )
                    )
                    continue
                result.parameters.append(
                    ParameterDef(
                        name=parameter_name,
                        label=str(values.get("label") or parameter_name),
                        description=str(values.get("description") or ""),
                        type=parameter_type,
                        default=default_value,
                        min=values.get("min"),
                        max=values.get("max"),
                        unit=values.get("unit"),
                        enum_values=values.get("enum_values"),
                    )
                )

            values = _decorator_values(decorator, "port", result.diagnostics)
            if values is not None:
                port_id = str(values.get("id") or statement.name)
                direction = values.get("direction")
                if port_id in port_ids:
                    result.diagnostics.append(
                        SourceDiagnostic(
                            message=f"Duplicate port '{port_id}'.",
                            line=statement.lineno,
                            column=statement.col_offset + 1,
                            code="duplicate-port",
                        )
                    )
                    continue
                port_ids.add(port_id)
                if direction not in {"input", "output"}:
                    result.diagnostics.append(
                        SourceDiagnostic(
                            message=f"Port '{port_id}' needs direction 'input' or 'output'.",
                            line=statement.lineno,
                            column=statement.col_offset + 1,
                            code="invalid-port",
                        )
                    )
                    continue
                result.ports.append(
                    PortDef(
                        id=port_id,
                        direction=direction,
                        label=str(values.get("label") or port_id),
                    )
                )

    has_delegation = bool(
        result.base_component_id or result.base_nir_type or result.base_pipeline_type
    )
    if not has_delegation:
        if set(result.canvases) & {"training", "eval"}:
            if "to_pipeline" not in method_names:
                result.diagnostics.append(
                    SourceDiagnostic(
                        message="Implement to_pipeline() or declare a base pipeline type.",
                        line=class_node.lineno,
                        column=class_node.col_offset + 1,
                        code="missing-pipeline-implementation",
                    )
                )
            return result
        for framework in result.frameworks:
            if f"to_{framework}" not in method_names:
                result.diagnostics.append(
                    SourceDiagnostic(
                        message=(
                            f"Implement to_{framework}() or declare a base component/NIR type."
                        ),
                        line=class_node.lineno,
                        column=class_node.col_offset + 1,
                        code="missing-framework-implementation",
                    )
                )
    return result


def inject_stable_node_id(source: str, node_id: str) -> str:
    """Insert or replace a literal ``node_id`` assignment in the node class."""
    assignment = f'    node_id = "{node_id}"'
    pattern = re.compile(r"^(?P<indent>\s*)node_id\s*=\s*[^\n]+$", re.MULTILINE)
    if pattern.search(source):
        return pattern.sub(assignment, source, count=1)

    tree = ast.parse(source)
    class_node = next(node for node in tree.body if isinstance(node, ast.ClassDef))
    lines = source.splitlines()
    lines.insert(class_node.lineno, assignment)
    suffix = "\n" if source.endswith("\n") else ""
    return "\n".join(lines) + suffix
