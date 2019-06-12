// Code generated from XsParser.g4 by ANTLR 4.7.2. DO NOT EDIT.

package parser // XsParser

import "github.com/antlr/antlr4/runtime/Go/antlr"

// BaseXsParserListener is a complete listener for a parse tree produced by XsParser.
type BaseXsParserListener struct{}

var _ XsParserListener = &BaseXsParserListener{}

// VisitTerminal is called when a terminal node is visited.
func (s *BaseXsParserListener) VisitTerminal(node antlr.TerminalNode) {}

// VisitErrorNode is called when an error node is visited.
func (s *BaseXsParserListener) VisitErrorNode(node antlr.ErrorNode) {}

// EnterEveryRule is called when any rule is entered.
func (s *BaseXsParserListener) EnterEveryRule(ctx antlr.ParserRuleContext) {}

// ExitEveryRule is called when any rule is exited.
func (s *BaseXsParserListener) ExitEveryRule(ctx antlr.ParserRuleContext) {}

// EnterProgram is called when production program is entered.
func (s *BaseXsParserListener) EnterProgram(ctx *ProgramContext) {}

// ExitProgram is called when production program is exited.
func (s *BaseXsParserListener) ExitProgram(ctx *ProgramContext) {}

// EnterStatement is called when production statement is entered.
func (s *BaseXsParserListener) EnterStatement(ctx *StatementContext) {}

// ExitStatement is called when production statement is exited.
func (s *BaseXsParserListener) ExitStatement(ctx *StatementContext) {}

// EnterExportStatement is called when production exportStatement is entered.
func (s *BaseXsParserListener) EnterExportStatement(ctx *ExportStatementContext) {}

// ExitExportStatement is called when production exportStatement is exited.
func (s *BaseXsParserListener) ExitExportStatement(ctx *ExportStatementContext) {}

// EnterImportStatement is called when production importStatement is entered.
func (s *BaseXsParserListener) EnterImportStatement(ctx *ImportStatementContext) {}

// ExitImportStatement is called when production importStatement is exited.
func (s *BaseXsParserListener) ExitImportStatement(ctx *ImportStatementContext) {}

// EnterNamespaceSupportStatement is called when production namespaceSupportStatement is entered.
func (s *BaseXsParserListener) EnterNamespaceSupportStatement(ctx *NamespaceSupportStatementContext) {}

// ExitNamespaceSupportStatement is called when production namespaceSupportStatement is exited.
func (s *BaseXsParserListener) ExitNamespaceSupportStatement(ctx *NamespaceSupportStatementContext) {}

// EnterEnumStatement is called when production enumStatement is entered.
func (s *BaseXsParserListener) EnterEnumStatement(ctx *EnumStatementContext) {}

// ExitEnumStatement is called when production enumStatement is exited.
func (s *BaseXsParserListener) ExitEnumStatement(ctx *EnumStatementContext) {}

// EnterEnumSupportStatement is called when production enumSupportStatement is entered.
func (s *BaseXsParserListener) EnterEnumSupportStatement(ctx *EnumSupportStatementContext) {}

// ExitEnumSupportStatement is called when production enumSupportStatement is exited.
func (s *BaseXsParserListener) ExitEnumSupportStatement(ctx *EnumSupportStatementContext) {}

// EnterNamespaceVariableStatement is called when production namespaceVariableStatement is entered.
func (s *BaseXsParserListener) EnterNamespaceVariableStatement(ctx *NamespaceVariableStatementContext) {
}

// ExitNamespaceVariableStatement is called when production namespaceVariableStatement is exited.
func (s *BaseXsParserListener) ExitNamespaceVariableStatement(ctx *NamespaceVariableStatementContext) {
}

// EnterNamespaceControlStatement is called when production namespaceControlStatement is entered.
func (s *BaseXsParserListener) EnterNamespaceControlStatement(ctx *NamespaceControlStatementContext) {}

// ExitNamespaceControlStatement is called when production namespaceControlStatement is exited.
func (s *BaseXsParserListener) ExitNamespaceControlStatement(ctx *NamespaceControlStatementContext) {}

// EnterNamespaceConstantStatement is called when production namespaceConstantStatement is entered.
func (s *BaseXsParserListener) EnterNamespaceConstantStatement(ctx *NamespaceConstantStatementContext) {
}

// ExitNamespaceConstantStatement is called when production namespaceConstantStatement is exited.
func (s *BaseXsParserListener) ExitNamespaceConstantStatement(ctx *NamespaceConstantStatementContext) {
}

// EnterNamespaceFunctionStatement is called when production namespaceFunctionStatement is entered.
func (s *BaseXsParserListener) EnterNamespaceFunctionStatement(ctx *NamespaceFunctionStatementContext) {
}

// ExitNamespaceFunctionStatement is called when production namespaceFunctionStatement is exited.
func (s *BaseXsParserListener) ExitNamespaceFunctionStatement(ctx *NamespaceFunctionStatementContext) {
}

// EnterPackageStatement is called when production packageStatement is entered.
func (s *BaseXsParserListener) EnterPackageStatement(ctx *PackageStatementContext) {}

// ExitPackageStatement is called when production packageStatement is exited.
func (s *BaseXsParserListener) ExitPackageStatement(ctx *PackageStatementContext) {}

// EnterPackageNewStatement is called when production packageNewStatement is entered.
func (s *BaseXsParserListener) EnterPackageNewStatement(ctx *PackageNewStatementContext) {}

// ExitPackageNewStatement is called when production packageNewStatement is exited.
func (s *BaseXsParserListener) ExitPackageNewStatement(ctx *PackageNewStatementContext) {}

// EnterParameterClausePackage is called when production parameterClausePackage is entered.
func (s *BaseXsParserListener) EnterParameterClausePackage(ctx *ParameterClausePackageContext) {}

// ExitParameterClausePackage is called when production parameterClausePackage is exited.
func (s *BaseXsParserListener) ExitParameterClausePackage(ctx *ParameterClausePackageContext) {}

// EnterPackageSupportStatement is called when production packageSupportStatement is entered.
func (s *BaseXsParserListener) EnterPackageSupportStatement(ctx *PackageSupportStatementContext) {}

// ExitPackageSupportStatement is called when production packageSupportStatement is exited.
func (s *BaseXsParserListener) ExitPackageSupportStatement(ctx *PackageSupportStatementContext) {}

// EnterPackageFunctionStatement is called when production packageFunctionStatement is entered.
func (s *BaseXsParserListener) EnterPackageFunctionStatement(ctx *PackageFunctionStatementContext) {}

// ExitPackageFunctionStatement is called when production packageFunctionStatement is exited.
func (s *BaseXsParserListener) ExitPackageFunctionStatement(ctx *PackageFunctionStatementContext) {}

// EnterPackageOverrideFunctionStatement is called when production packageOverrideFunctionStatement is entered.
func (s *BaseXsParserListener) EnterPackageOverrideFunctionStatement(ctx *PackageOverrideFunctionStatementContext) {
}

// ExitPackageOverrideFunctionStatement is called when production packageOverrideFunctionStatement is exited.
func (s *BaseXsParserListener) ExitPackageOverrideFunctionStatement(ctx *PackageOverrideFunctionStatementContext) {
}

// EnterPackageVariableStatement is called when production packageVariableStatement is entered.
func (s *BaseXsParserListener) EnterPackageVariableStatement(ctx *PackageVariableStatementContext) {}

// ExitPackageVariableStatement is called when production packageVariableStatement is exited.
func (s *BaseXsParserListener) ExitPackageVariableStatement(ctx *PackageVariableStatementContext) {}

// EnterPackageControlStatement is called when production packageControlStatement is entered.
func (s *BaseXsParserListener) EnterPackageControlStatement(ctx *PackageControlStatementContext) {}

// ExitPackageControlStatement is called when production packageControlStatement is exited.
func (s *BaseXsParserListener) ExitPackageControlStatement(ctx *PackageControlStatementContext) {}

// EnterPackageControlSubStatement is called when production packageControlSubStatement is entered.
func (s *BaseXsParserListener) EnterPackageControlSubStatement(ctx *PackageControlSubStatementContext) {
}

// ExitPackageControlSubStatement is called when production packageControlSubStatement is exited.
func (s *BaseXsParserListener) ExitPackageControlSubStatement(ctx *PackageControlSubStatementContext) {
}

// EnterPackageOverrideStatement is called when production packageOverrideStatement is entered.
func (s *BaseXsParserListener) EnterPackageOverrideStatement(ctx *PackageOverrideStatementContext) {}

// ExitPackageOverrideStatement is called when production packageOverrideStatement is exited.
func (s *BaseXsParserListener) ExitPackageOverrideStatement(ctx *PackageOverrideStatementContext) {}

// EnterPackageExtensionStatement is called when production packageExtensionStatement is entered.
func (s *BaseXsParserListener) EnterPackageExtensionStatement(ctx *PackageExtensionStatementContext) {}

// ExitPackageExtensionStatement is called when production packageExtensionStatement is exited.
func (s *BaseXsParserListener) ExitPackageExtensionStatement(ctx *PackageExtensionStatementContext) {}

// EnterProtocolStatement is called when production protocolStatement is entered.
func (s *BaseXsParserListener) EnterProtocolStatement(ctx *ProtocolStatementContext) {}

// ExitProtocolStatement is called when production protocolStatement is exited.
func (s *BaseXsParserListener) ExitProtocolStatement(ctx *ProtocolStatementContext) {}

// EnterProtocolSupportStatement is called when production protocolSupportStatement is entered.
func (s *BaseXsParserListener) EnterProtocolSupportStatement(ctx *ProtocolSupportStatementContext) {}

// ExitProtocolSupportStatement is called when production protocolSupportStatement is exited.
func (s *BaseXsParserListener) ExitProtocolSupportStatement(ctx *ProtocolSupportStatementContext) {}

// EnterProtocolControlStatement is called when production protocolControlStatement is entered.
func (s *BaseXsParserListener) EnterProtocolControlStatement(ctx *ProtocolControlStatementContext) {}

// ExitProtocolControlStatement is called when production protocolControlStatement is exited.
func (s *BaseXsParserListener) ExitProtocolControlStatement(ctx *ProtocolControlStatementContext) {}

// EnterProtocolControlSubStatement is called when production protocolControlSubStatement is entered.
func (s *BaseXsParserListener) EnterProtocolControlSubStatement(ctx *ProtocolControlSubStatementContext) {
}

// ExitProtocolControlSubStatement is called when production protocolControlSubStatement is exited.
func (s *BaseXsParserListener) ExitProtocolControlSubStatement(ctx *ProtocolControlSubStatementContext) {
}

// EnterProtocolFunctionStatement is called when production protocolFunctionStatement is entered.
func (s *BaseXsParserListener) EnterProtocolFunctionStatement(ctx *ProtocolFunctionStatementContext) {}

// ExitProtocolFunctionStatement is called when production protocolFunctionStatement is exited.
func (s *BaseXsParserListener) ExitProtocolFunctionStatement(ctx *ProtocolFunctionStatementContext) {}

// EnterProtocolImplementSupportStatement is called when production protocolImplementSupportStatement is entered.
func (s *BaseXsParserListener) EnterProtocolImplementSupportStatement(ctx *ProtocolImplementSupportStatementContext) {
}

// ExitProtocolImplementSupportStatement is called when production protocolImplementSupportStatement is exited.
func (s *BaseXsParserListener) ExitProtocolImplementSupportStatement(ctx *ProtocolImplementSupportStatementContext) {
}

// EnterProtocolImplementStatement is called when production protocolImplementStatement is entered.
func (s *BaseXsParserListener) EnterProtocolImplementStatement(ctx *ProtocolImplementStatementContext) {
}

// ExitProtocolImplementStatement is called when production protocolImplementStatement is exited.
func (s *BaseXsParserListener) ExitProtocolImplementStatement(ctx *ProtocolImplementStatementContext) {
}

// EnterImplementControlStatement is called when production implementControlStatement is entered.
func (s *BaseXsParserListener) EnterImplementControlStatement(ctx *ImplementControlStatementContext) {}

// ExitImplementControlStatement is called when production implementControlStatement is exited.
func (s *BaseXsParserListener) ExitImplementControlStatement(ctx *ImplementControlStatementContext) {}

// EnterImplementFunctionStatement is called when production implementFunctionStatement is entered.
func (s *BaseXsParserListener) EnterImplementFunctionStatement(ctx *ImplementFunctionStatementContext) {
}

// ExitImplementFunctionStatement is called when production implementFunctionStatement is exited.
func (s *BaseXsParserListener) ExitImplementFunctionStatement(ctx *ImplementFunctionStatementContext) {
}

// EnterImplementEventStatement is called when production implementEventStatement is entered.
func (s *BaseXsParserListener) EnterImplementEventStatement(ctx *ImplementEventStatementContext) {}

// ExitImplementEventStatement is called when production implementEventStatement is exited.
func (s *BaseXsParserListener) ExitImplementEventStatement(ctx *ImplementEventStatementContext) {}

// EnterFunctionStatement is called when production functionStatement is entered.
func (s *BaseXsParserListener) EnterFunctionStatement(ctx *FunctionStatementContext) {}

// ExitFunctionStatement is called when production functionStatement is exited.
func (s *BaseXsParserListener) ExitFunctionStatement(ctx *FunctionStatementContext) {}

// EnterReturnStatement is called when production returnStatement is entered.
func (s *BaseXsParserListener) EnterReturnStatement(ctx *ReturnStatementContext) {}

// ExitReturnStatement is called when production returnStatement is exited.
func (s *BaseXsParserListener) ExitReturnStatement(ctx *ReturnStatementContext) {}

// EnterParameterClauseIn is called when production parameterClauseIn is entered.
func (s *BaseXsParserListener) EnterParameterClauseIn(ctx *ParameterClauseInContext) {}

// ExitParameterClauseIn is called when production parameterClauseIn is exited.
func (s *BaseXsParserListener) ExitParameterClauseIn(ctx *ParameterClauseInContext) {}

// EnterParameterClauseOut is called when production parameterClauseOut is entered.
func (s *BaseXsParserListener) EnterParameterClauseOut(ctx *ParameterClauseOutContext) {}

// ExitParameterClauseOut is called when production parameterClauseOut is exited.
func (s *BaseXsParserListener) ExitParameterClauseOut(ctx *ParameterClauseOutContext) {}

// EnterParameter is called when production parameter is entered.
func (s *BaseXsParserListener) EnterParameter(ctx *ParameterContext) {}

// ExitParameter is called when production parameter is exited.
func (s *BaseXsParserListener) ExitParameter(ctx *ParameterContext) {}

// EnterFunctionSupportStatement is called when production functionSupportStatement is entered.
func (s *BaseXsParserListener) EnterFunctionSupportStatement(ctx *FunctionSupportStatementContext) {}

// ExitFunctionSupportStatement is called when production functionSupportStatement is exited.
func (s *BaseXsParserListener) ExitFunctionSupportStatement(ctx *FunctionSupportStatementContext) {}

// EnterJudgeCaseStatement is called when production judgeCaseStatement is entered.
func (s *BaseXsParserListener) EnterJudgeCaseStatement(ctx *JudgeCaseStatementContext) {}

// ExitJudgeCaseStatement is called when production judgeCaseStatement is exited.
func (s *BaseXsParserListener) ExitJudgeCaseStatement(ctx *JudgeCaseStatementContext) {}

// EnterCaseDefaultStatement is called when production caseDefaultStatement is entered.
func (s *BaseXsParserListener) EnterCaseDefaultStatement(ctx *CaseDefaultStatementContext) {}

// ExitCaseDefaultStatement is called when production caseDefaultStatement is exited.
func (s *BaseXsParserListener) ExitCaseDefaultStatement(ctx *CaseDefaultStatementContext) {}

// EnterCaseExprStatement is called when production caseExprStatement is entered.
func (s *BaseXsParserListener) EnterCaseExprStatement(ctx *CaseExprStatementContext) {}

// ExitCaseExprStatement is called when production caseExprStatement is exited.
func (s *BaseXsParserListener) ExitCaseExprStatement(ctx *CaseExprStatementContext) {}

// EnterCaseStatement is called when production caseStatement is entered.
func (s *BaseXsParserListener) EnterCaseStatement(ctx *CaseStatementContext) {}

// ExitCaseStatement is called when production caseStatement is exited.
func (s *BaseXsParserListener) ExitCaseStatement(ctx *CaseStatementContext) {}

// EnterJudgeStatement is called when production judgeStatement is entered.
func (s *BaseXsParserListener) EnterJudgeStatement(ctx *JudgeStatementContext) {}

// ExitJudgeStatement is called when production judgeStatement is exited.
func (s *BaseXsParserListener) ExitJudgeStatement(ctx *JudgeStatementContext) {}

// EnterJudgeElseStatement is called when production judgeElseStatement is entered.
func (s *BaseXsParserListener) EnterJudgeElseStatement(ctx *JudgeElseStatementContext) {}

// ExitJudgeElseStatement is called when production judgeElseStatement is exited.
func (s *BaseXsParserListener) ExitJudgeElseStatement(ctx *JudgeElseStatementContext) {}

// EnterJudgeIfStatement is called when production judgeIfStatement is entered.
func (s *BaseXsParserListener) EnterJudgeIfStatement(ctx *JudgeIfStatementContext) {}

// ExitJudgeIfStatement is called when production judgeIfStatement is exited.
func (s *BaseXsParserListener) ExitJudgeIfStatement(ctx *JudgeIfStatementContext) {}

// EnterJudgeElseIfStatement is called when production judgeElseIfStatement is entered.
func (s *BaseXsParserListener) EnterJudgeElseIfStatement(ctx *JudgeElseIfStatementContext) {}

// ExitJudgeElseIfStatement is called when production judgeElseIfStatement is exited.
func (s *BaseXsParserListener) ExitJudgeElseIfStatement(ctx *JudgeElseIfStatementContext) {}

// EnterLoopStatement is called when production loopStatement is entered.
func (s *BaseXsParserListener) EnterLoopStatement(ctx *LoopStatementContext) {}

// ExitLoopStatement is called when production loopStatement is exited.
func (s *BaseXsParserListener) ExitLoopStatement(ctx *LoopStatementContext) {}

// EnterLoopEachStatement is called when production loopEachStatement is entered.
func (s *BaseXsParserListener) EnterLoopEachStatement(ctx *LoopEachStatementContext) {}

// ExitLoopEachStatement is called when production loopEachStatement is exited.
func (s *BaseXsParserListener) ExitLoopEachStatement(ctx *LoopEachStatementContext) {}

// EnterLoopCaseStatement is called when production loopCaseStatement is entered.
func (s *BaseXsParserListener) EnterLoopCaseStatement(ctx *LoopCaseStatementContext) {}

// ExitLoopCaseStatement is called when production loopCaseStatement is exited.
func (s *BaseXsParserListener) ExitLoopCaseStatement(ctx *LoopCaseStatementContext) {}

// EnterLoopInfiniteStatement is called when production loopInfiniteStatement is entered.
func (s *BaseXsParserListener) EnterLoopInfiniteStatement(ctx *LoopInfiniteStatementContext) {}

// ExitLoopInfiniteStatement is called when production loopInfiniteStatement is exited.
func (s *BaseXsParserListener) ExitLoopInfiniteStatement(ctx *LoopInfiniteStatementContext) {}

// EnterLoopJumpStatement is called when production loopJumpStatement is entered.
func (s *BaseXsParserListener) EnterLoopJumpStatement(ctx *LoopJumpStatementContext) {}

// ExitLoopJumpStatement is called when production loopJumpStatement is exited.
func (s *BaseXsParserListener) ExitLoopJumpStatement(ctx *LoopJumpStatementContext) {}

// EnterLoopContinueStatement is called when production loopContinueStatement is entered.
func (s *BaseXsParserListener) EnterLoopContinueStatement(ctx *LoopContinueStatementContext) {}

// ExitLoopContinueStatement is called when production loopContinueStatement is exited.
func (s *BaseXsParserListener) ExitLoopContinueStatement(ctx *LoopContinueStatementContext) {}

// EnterCheckStatement is called when production checkStatement is entered.
func (s *BaseXsParserListener) EnterCheckStatement(ctx *CheckStatementContext) {}

// ExitCheckStatement is called when production checkStatement is exited.
func (s *BaseXsParserListener) ExitCheckStatement(ctx *CheckStatementContext) {}

// EnterUsingStatement is called when production usingStatement is entered.
func (s *BaseXsParserListener) EnterUsingStatement(ctx *UsingStatementContext) {}

// ExitUsingStatement is called when production usingStatement is exited.
func (s *BaseXsParserListener) ExitUsingStatement(ctx *UsingStatementContext) {}

// EnterCheckErrorStatement is called when production checkErrorStatement is entered.
func (s *BaseXsParserListener) EnterCheckErrorStatement(ctx *CheckErrorStatementContext) {}

// ExitCheckErrorStatement is called when production checkErrorStatement is exited.
func (s *BaseXsParserListener) ExitCheckErrorStatement(ctx *CheckErrorStatementContext) {}

// EnterCheckFinallyStatment is called when production checkFinallyStatment is entered.
func (s *BaseXsParserListener) EnterCheckFinallyStatment(ctx *CheckFinallyStatmentContext) {}

// ExitCheckFinallyStatment is called when production checkFinallyStatment is exited.
func (s *BaseXsParserListener) ExitCheckFinallyStatment(ctx *CheckFinallyStatmentContext) {}

// EnterReportStatement is called when production reportStatement is entered.
func (s *BaseXsParserListener) EnterReportStatement(ctx *ReportStatementContext) {}

// ExitReportStatement is called when production reportStatement is exited.
func (s *BaseXsParserListener) ExitReportStatement(ctx *ReportStatementContext) {}

// EnterIteratorStatement is called when production iteratorStatement is entered.
func (s *BaseXsParserListener) EnterIteratorStatement(ctx *IteratorStatementContext) {}

// ExitIteratorStatement is called when production iteratorStatement is exited.
func (s *BaseXsParserListener) ExitIteratorStatement(ctx *IteratorStatementContext) {}

// EnterVariableStatement is called when production variableStatement is entered.
func (s *BaseXsParserListener) EnterVariableStatement(ctx *VariableStatementContext) {}

// ExitVariableStatement is called when production variableStatement is exited.
func (s *BaseXsParserListener) ExitVariableStatement(ctx *VariableStatementContext) {}

// EnterVariableDeclaredStatement is called when production variableDeclaredStatement is entered.
func (s *BaseXsParserListener) EnterVariableDeclaredStatement(ctx *VariableDeclaredStatementContext) {}

// ExitVariableDeclaredStatement is called when production variableDeclaredStatement is exited.
func (s *BaseXsParserListener) ExitVariableDeclaredStatement(ctx *VariableDeclaredStatementContext) {}

// EnterAssignStatement is called when production assignStatement is entered.
func (s *BaseXsParserListener) EnterAssignStatement(ctx *AssignStatementContext) {}

// ExitAssignStatement is called when production assignStatement is exited.
func (s *BaseXsParserListener) ExitAssignStatement(ctx *AssignStatementContext) {}

// EnterExpressionStatement is called when production expressionStatement is entered.
func (s *BaseXsParserListener) EnterExpressionStatement(ctx *ExpressionStatementContext) {}

// ExitExpressionStatement is called when production expressionStatement is exited.
func (s *BaseXsParserListener) ExitExpressionStatement(ctx *ExpressionStatementContext) {}

// EnterPrimaryExpression is called when production primaryExpression is entered.
func (s *BaseXsParserListener) EnterPrimaryExpression(ctx *PrimaryExpressionContext) {}

// ExitPrimaryExpression is called when production primaryExpression is exited.
func (s *BaseXsParserListener) ExitPrimaryExpression(ctx *PrimaryExpressionContext) {}

// EnterExpression is called when production expression is entered.
func (s *BaseXsParserListener) EnterExpression(ctx *ExpressionContext) {}

// ExitExpression is called when production expression is exited.
func (s *BaseXsParserListener) ExitExpression(ctx *ExpressionContext) {}

// EnterCallBase is called when production callBase is entered.
func (s *BaseXsParserListener) EnterCallBase(ctx *CallBaseContext) {}

// ExitCallBase is called when production callBase is exited.
func (s *BaseXsParserListener) ExitCallBase(ctx *CallBaseContext) {}

// EnterCallSelf is called when production callSelf is entered.
func (s *BaseXsParserListener) EnterCallSelf(ctx *CallSelfContext) {}

// ExitCallSelf is called when production callSelf is exited.
func (s *BaseXsParserListener) ExitCallSelf(ctx *CallSelfContext) {}

// EnterCallNameSpace is called when production callNameSpace is entered.
func (s *BaseXsParserListener) EnterCallNameSpace(ctx *CallNameSpaceContext) {}

// ExitCallNameSpace is called when production callNameSpace is exited.
func (s *BaseXsParserListener) ExitCallNameSpace(ctx *CallNameSpaceContext) {}

// EnterCallExpression is called when production callExpression is entered.
func (s *BaseXsParserListener) EnterCallExpression(ctx *CallExpressionContext) {}

// ExitCallExpression is called when production callExpression is exited.
func (s *BaseXsParserListener) ExitCallExpression(ctx *CallExpressionContext) {}

// EnterTuple is called when production tuple is entered.
func (s *BaseXsParserListener) EnterTuple(ctx *TupleContext) {}

// ExitTuple is called when production tuple is exited.
func (s *BaseXsParserListener) ExitTuple(ctx *TupleContext) {}

// EnterExpressionList is called when production expressionList is entered.
func (s *BaseXsParserListener) EnterExpressionList(ctx *ExpressionListContext) {}

// ExitExpressionList is called when production expressionList is exited.
func (s *BaseXsParserListener) ExitExpressionList(ctx *ExpressionListContext) {}

// EnterAnnotationSupport is called when production annotationSupport is entered.
func (s *BaseXsParserListener) EnterAnnotationSupport(ctx *AnnotationSupportContext) {}

// ExitAnnotationSupport is called when production annotationSupport is exited.
func (s *BaseXsParserListener) ExitAnnotationSupport(ctx *AnnotationSupportContext) {}

// EnterAnnotation is called when production annotation is entered.
func (s *BaseXsParserListener) EnterAnnotation(ctx *AnnotationContext) {}

// ExitAnnotation is called when production annotation is exited.
func (s *BaseXsParserListener) ExitAnnotation(ctx *AnnotationContext) {}

// EnterAnnotationList is called when production annotationList is entered.
func (s *BaseXsParserListener) EnterAnnotationList(ctx *AnnotationListContext) {}

// ExitAnnotationList is called when production annotationList is exited.
func (s *BaseXsParserListener) ExitAnnotationList(ctx *AnnotationListContext) {}

// EnterAnnotationItem is called when production annotationItem is entered.
func (s *BaseXsParserListener) EnterAnnotationItem(ctx *AnnotationItemContext) {}

// ExitAnnotationItem is called when production annotationItem is exited.
func (s *BaseXsParserListener) ExitAnnotationItem(ctx *AnnotationItemContext) {}

// EnterAnnotationAssign is called when production annotationAssign is entered.
func (s *BaseXsParserListener) EnterAnnotationAssign(ctx *AnnotationAssignContext) {}

// ExitAnnotationAssign is called when production annotationAssign is exited.
func (s *BaseXsParserListener) ExitAnnotationAssign(ctx *AnnotationAssignContext) {}

// EnterCallFunc is called when production callFunc is entered.
func (s *BaseXsParserListener) EnterCallFunc(ctx *CallFuncContext) {}

// ExitCallFunc is called when production callFunc is exited.
func (s *BaseXsParserListener) ExitCallFunc(ctx *CallFuncContext) {}

// EnterCallElement is called when production callElement is entered.
func (s *BaseXsParserListener) EnterCallElement(ctx *CallElementContext) {}

// ExitCallElement is called when production callElement is exited.
func (s *BaseXsParserListener) ExitCallElement(ctx *CallElementContext) {}

// EnterCallPkg is called when production callPkg is entered.
func (s *BaseXsParserListener) EnterCallPkg(ctx *CallPkgContext) {}

// ExitCallPkg is called when production callPkg is exited.
func (s *BaseXsParserListener) ExitCallPkg(ctx *CallPkgContext) {}

// EnterCallNew is called when production callNew is entered.
func (s *BaseXsParserListener) EnterCallNew(ctx *CallNewContext) {}

// ExitCallNew is called when production callNew is exited.
func (s *BaseXsParserListener) ExitCallNew(ctx *CallNewContext) {}

// EnterGetType is called when production getType is entered.
func (s *BaseXsParserListener) EnterGetType(ctx *GetTypeContext) {}

// ExitGetType is called when production getType is exited.
func (s *BaseXsParserListener) ExitGetType(ctx *GetTypeContext) {}

// EnterTypeConversion is called when production typeConversion is entered.
func (s *BaseXsParserListener) EnterTypeConversion(ctx *TypeConversionContext) {}

// ExitTypeConversion is called when production typeConversion is exited.
func (s *BaseXsParserListener) ExitTypeConversion(ctx *TypeConversionContext) {}

// EnterPkgAssign is called when production pkgAssign is entered.
func (s *BaseXsParserListener) EnterPkgAssign(ctx *PkgAssignContext) {}

// ExitPkgAssign is called when production pkgAssign is exited.
func (s *BaseXsParserListener) ExitPkgAssign(ctx *PkgAssignContext) {}

// EnterPkgAssignElement is called when production pkgAssignElement is entered.
func (s *BaseXsParserListener) EnterPkgAssignElement(ctx *PkgAssignElementContext) {}

// ExitPkgAssignElement is called when production pkgAssignElement is exited.
func (s *BaseXsParserListener) ExitPkgAssignElement(ctx *PkgAssignElementContext) {}

// EnterListAssign is called when production listAssign is entered.
func (s *BaseXsParserListener) EnterListAssign(ctx *ListAssignContext) {}

// ExitListAssign is called when production listAssign is exited.
func (s *BaseXsParserListener) ExitListAssign(ctx *ListAssignContext) {}

// EnterSetAssign is called when production setAssign is entered.
func (s *BaseXsParserListener) EnterSetAssign(ctx *SetAssignContext) {}

// ExitSetAssign is called when production setAssign is exited.
func (s *BaseXsParserListener) ExitSetAssign(ctx *SetAssignContext) {}

// EnterDictionaryAssign is called when production dictionaryAssign is entered.
func (s *BaseXsParserListener) EnterDictionaryAssign(ctx *DictionaryAssignContext) {}

// ExitDictionaryAssign is called when production dictionaryAssign is exited.
func (s *BaseXsParserListener) ExitDictionaryAssign(ctx *DictionaryAssignContext) {}

// EnterCallAwait is called when production callAwait is entered.
func (s *BaseXsParserListener) EnterCallAwait(ctx *CallAwaitContext) {}

// ExitCallAwait is called when production callAwait is exited.
func (s *BaseXsParserListener) ExitCallAwait(ctx *CallAwaitContext) {}

// EnterList is called when production list is entered.
func (s *BaseXsParserListener) EnterList(ctx *ListContext) {}

// ExitList is called when production list is exited.
func (s *BaseXsParserListener) ExitList(ctx *ListContext) {}

// EnterSet is called when production set is entered.
func (s *BaseXsParserListener) EnterSet(ctx *SetContext) {}

// ExitSet is called when production set is exited.
func (s *BaseXsParserListener) ExitSet(ctx *SetContext) {}

// EnterDictionary is called when production dictionary is entered.
func (s *BaseXsParserListener) EnterDictionary(ctx *DictionaryContext) {}

// ExitDictionary is called when production dictionary is exited.
func (s *BaseXsParserListener) ExitDictionary(ctx *DictionaryContext) {}

// EnterDictionaryElement is called when production dictionaryElement is entered.
func (s *BaseXsParserListener) EnterDictionaryElement(ctx *DictionaryElementContext) {}

// ExitDictionaryElement is called when production dictionaryElement is exited.
func (s *BaseXsParserListener) ExitDictionaryElement(ctx *DictionaryElementContext) {}

// EnterSlice is called when production slice is entered.
func (s *BaseXsParserListener) EnterSlice(ctx *SliceContext) {}

// ExitSlice is called when production slice is exited.
func (s *BaseXsParserListener) ExitSlice(ctx *SliceContext) {}

// EnterSliceFull is called when production sliceFull is entered.
func (s *BaseXsParserListener) EnterSliceFull(ctx *SliceFullContext) {}

// ExitSliceFull is called when production sliceFull is exited.
func (s *BaseXsParserListener) ExitSliceFull(ctx *SliceFullContext) {}

// EnterSliceStart is called when production sliceStart is entered.
func (s *BaseXsParserListener) EnterSliceStart(ctx *SliceStartContext) {}

// ExitSliceStart is called when production sliceStart is exited.
func (s *BaseXsParserListener) ExitSliceStart(ctx *SliceStartContext) {}

// EnterSliceEnd is called when production sliceEnd is entered.
func (s *BaseXsParserListener) EnterSliceEnd(ctx *SliceEndContext) {}

// ExitSliceEnd is called when production sliceEnd is exited.
func (s *BaseXsParserListener) ExitSliceEnd(ctx *SliceEndContext) {}

// EnterNameSpace is called when production nameSpace is entered.
func (s *BaseXsParserListener) EnterNameSpace(ctx *NameSpaceContext) {}

// ExitNameSpace is called when production nameSpace is exited.
func (s *BaseXsParserListener) ExitNameSpace(ctx *NameSpaceContext) {}

// EnterNameSpaceItem is called when production nameSpaceItem is entered.
func (s *BaseXsParserListener) EnterNameSpaceItem(ctx *NameSpaceItemContext) {}

// ExitNameSpaceItem is called when production nameSpaceItem is exited.
func (s *BaseXsParserListener) ExitNameSpaceItem(ctx *NameSpaceItemContext) {}

// EnterName is called when production name is entered.
func (s *BaseXsParserListener) EnterName(ctx *NameContext) {}

// ExitName is called when production name is exited.
func (s *BaseXsParserListener) ExitName(ctx *NameContext) {}

// EnterTemplateDefine is called when production templateDefine is entered.
func (s *BaseXsParserListener) EnterTemplateDefine(ctx *TemplateDefineContext) {}

// ExitTemplateDefine is called when production templateDefine is exited.
func (s *BaseXsParserListener) ExitTemplateDefine(ctx *TemplateDefineContext) {}

// EnterTemplateDefineItem is called when production templateDefineItem is entered.
func (s *BaseXsParserListener) EnterTemplateDefineItem(ctx *TemplateDefineItemContext) {}

// ExitTemplateDefineItem is called when production templateDefineItem is exited.
func (s *BaseXsParserListener) ExitTemplateDefineItem(ctx *TemplateDefineItemContext) {}

// EnterTemplateCall is called when production templateCall is entered.
func (s *BaseXsParserListener) EnterTemplateCall(ctx *TemplateCallContext) {}

// ExitTemplateCall is called when production templateCall is exited.
func (s *BaseXsParserListener) ExitTemplateCall(ctx *TemplateCallContext) {}

// EnterLambda is called when production lambda is entered.
func (s *BaseXsParserListener) EnterLambda(ctx *LambdaContext) {}

// ExitLambda is called when production lambda is exited.
func (s *BaseXsParserListener) ExitLambda(ctx *LambdaContext) {}

// EnterLambdaIn is called when production lambdaIn is entered.
func (s *BaseXsParserListener) EnterLambdaIn(ctx *LambdaInContext) {}

// ExitLambdaIn is called when production lambdaIn is exited.
func (s *BaseXsParserListener) ExitLambdaIn(ctx *LambdaInContext) {}

// EnterPkgAnonymous is called when production pkgAnonymous is entered.
func (s *BaseXsParserListener) EnterPkgAnonymous(ctx *PkgAnonymousContext) {}

// ExitPkgAnonymous is called when production pkgAnonymous is exited.
func (s *BaseXsParserListener) ExitPkgAnonymous(ctx *PkgAnonymousContext) {}

// EnterPkgAnonymousAssign is called when production pkgAnonymousAssign is entered.
func (s *BaseXsParserListener) EnterPkgAnonymousAssign(ctx *PkgAnonymousAssignContext) {}

// ExitPkgAnonymousAssign is called when production pkgAnonymousAssign is exited.
func (s *BaseXsParserListener) ExitPkgAnonymousAssign(ctx *PkgAnonymousAssignContext) {}

// EnterPkgAnonymousAssignElement is called when production pkgAnonymousAssignElement is entered.
func (s *BaseXsParserListener) EnterPkgAnonymousAssignElement(ctx *PkgAnonymousAssignElementContext) {}

// ExitPkgAnonymousAssignElement is called when production pkgAnonymousAssignElement is exited.
func (s *BaseXsParserListener) ExitPkgAnonymousAssignElement(ctx *PkgAnonymousAssignElementContext) {}

// EnterFunctionExpression is called when production functionExpression is entered.
func (s *BaseXsParserListener) EnterFunctionExpression(ctx *FunctionExpressionContext) {}

// ExitFunctionExpression is called when production functionExpression is exited.
func (s *BaseXsParserListener) ExitFunctionExpression(ctx *FunctionExpressionContext) {}

// EnterAnonymousParameterClauseIn is called when production anonymousParameterClauseIn is entered.
func (s *BaseXsParserListener) EnterAnonymousParameterClauseIn(ctx *AnonymousParameterClauseInContext) {
}

// ExitAnonymousParameterClauseIn is called when production anonymousParameterClauseIn is exited.
func (s *BaseXsParserListener) ExitAnonymousParameterClauseIn(ctx *AnonymousParameterClauseInContext) {
}

// EnterTupleExpression is called when production tupleExpression is entered.
func (s *BaseXsParserListener) EnterTupleExpression(ctx *TupleExpressionContext) {}

// ExitTupleExpression is called when production tupleExpression is exited.
func (s *BaseXsParserListener) ExitTupleExpression(ctx *TupleExpressionContext) {}

// EnterPlusMinus is called when production plusMinus is entered.
func (s *BaseXsParserListener) EnterPlusMinus(ctx *PlusMinusContext) {}

// ExitPlusMinus is called when production plusMinus is exited.
func (s *BaseXsParserListener) ExitPlusMinus(ctx *PlusMinusContext) {}

// EnterNegate is called when production negate is entered.
func (s *BaseXsParserListener) EnterNegate(ctx *NegateContext) {}

// ExitNegate is called when production negate is exited.
func (s *BaseXsParserListener) ExitNegate(ctx *NegateContext) {}

// EnterLinq is called when production linq is entered.
func (s *BaseXsParserListener) EnterLinq(ctx *LinqContext) {}

// ExitLinq is called when production linq is exited.
func (s *BaseXsParserListener) ExitLinq(ctx *LinqContext) {}

// EnterLinqItem is called when production linqItem is entered.
func (s *BaseXsParserListener) EnterLinqItem(ctx *LinqItemContext) {}

// ExitLinqItem is called when production linqItem is exited.
func (s *BaseXsParserListener) ExitLinqItem(ctx *LinqItemContext) {}

// EnterLinqKeyword is called when production linqKeyword is entered.
func (s *BaseXsParserListener) EnterLinqKeyword(ctx *LinqKeywordContext) {}

// ExitLinqKeyword is called when production linqKeyword is exited.
func (s *BaseXsParserListener) ExitLinqKeyword(ctx *LinqKeywordContext) {}

// EnterLinqHeadKeyword is called when production linqHeadKeyword is entered.
func (s *BaseXsParserListener) EnterLinqHeadKeyword(ctx *LinqHeadKeywordContext) {}

// ExitLinqHeadKeyword is called when production linqHeadKeyword is exited.
func (s *BaseXsParserListener) ExitLinqHeadKeyword(ctx *LinqHeadKeywordContext) {}

// EnterLinqBodyKeyword is called when production linqBodyKeyword is entered.
func (s *BaseXsParserListener) EnterLinqBodyKeyword(ctx *LinqBodyKeywordContext) {}

// ExitLinqBodyKeyword is called when production linqBodyKeyword is exited.
func (s *BaseXsParserListener) ExitLinqBodyKeyword(ctx *LinqBodyKeywordContext) {}

// EnterStringExpression is called when production stringExpression is entered.
func (s *BaseXsParserListener) EnterStringExpression(ctx *StringExpressionContext) {}

// ExitStringExpression is called when production stringExpression is exited.
func (s *BaseXsParserListener) ExitStringExpression(ctx *StringExpressionContext) {}

// EnterStringExpressionElement is called when production stringExpressionElement is entered.
func (s *BaseXsParserListener) EnterStringExpressionElement(ctx *StringExpressionElementContext) {}

// ExitStringExpressionElement is called when production stringExpressionElement is exited.
func (s *BaseXsParserListener) ExitStringExpressionElement(ctx *StringExpressionElementContext) {}

// EnterDataStatement is called when production dataStatement is entered.
func (s *BaseXsParserListener) EnterDataStatement(ctx *DataStatementContext) {}

// ExitDataStatement is called when production dataStatement is exited.
func (s *BaseXsParserListener) ExitDataStatement(ctx *DataStatementContext) {}

// EnterFloatExpr is called when production floatExpr is entered.
func (s *BaseXsParserListener) EnterFloatExpr(ctx *FloatExprContext) {}

// ExitFloatExpr is called when production floatExpr is exited.
func (s *BaseXsParserListener) ExitFloatExpr(ctx *FloatExprContext) {}

// EnterIntegerExpr is called when production integerExpr is entered.
func (s *BaseXsParserListener) EnterIntegerExpr(ctx *IntegerExprContext) {}

// ExitIntegerExpr is called when production integerExpr is exited.
func (s *BaseXsParserListener) ExitIntegerExpr(ctx *IntegerExprContext) {}

// EnterTypeNotNull is called when production typeNotNull is entered.
func (s *BaseXsParserListener) EnterTypeNotNull(ctx *TypeNotNullContext) {}

// ExitTypeNotNull is called when production typeNotNull is exited.
func (s *BaseXsParserListener) ExitTypeNotNull(ctx *TypeNotNullContext) {}

// EnterTypeReference is called when production typeReference is entered.
func (s *BaseXsParserListener) EnterTypeReference(ctx *TypeReferenceContext) {}

// ExitTypeReference is called when production typeReference is exited.
func (s *BaseXsParserListener) ExitTypeReference(ctx *TypeReferenceContext) {}

// EnterTypeNullable is called when production typeNullable is entered.
func (s *BaseXsParserListener) EnterTypeNullable(ctx *TypeNullableContext) {}

// ExitTypeNullable is called when production typeNullable is exited.
func (s *BaseXsParserListener) ExitTypeNullable(ctx *TypeNullableContext) {}

// EnterTypeType is called when production typeType is entered.
func (s *BaseXsParserListener) EnterTypeType(ctx *TypeTypeContext) {}

// ExitTypeType is called when production typeType is exited.
func (s *BaseXsParserListener) ExitTypeType(ctx *TypeTypeContext) {}

// EnterTypeTuple is called when production typeTuple is entered.
func (s *BaseXsParserListener) EnterTypeTuple(ctx *TypeTupleContext) {}

// ExitTypeTuple is called when production typeTuple is exited.
func (s *BaseXsParserListener) ExitTypeTuple(ctx *TypeTupleContext) {}

// EnterTypeArray is called when production typeArray is entered.
func (s *BaseXsParserListener) EnterTypeArray(ctx *TypeArrayContext) {}

// ExitTypeArray is called when production typeArray is exited.
func (s *BaseXsParserListener) ExitTypeArray(ctx *TypeArrayContext) {}

// EnterTypeList is called when production typeList is entered.
func (s *BaseXsParserListener) EnterTypeList(ctx *TypeListContext) {}

// ExitTypeList is called when production typeList is exited.
func (s *BaseXsParserListener) ExitTypeList(ctx *TypeListContext) {}

// EnterTypeSet is called when production typeSet is entered.
func (s *BaseXsParserListener) EnterTypeSet(ctx *TypeSetContext) {}

// ExitTypeSet is called when production typeSet is exited.
func (s *BaseXsParserListener) ExitTypeSet(ctx *TypeSetContext) {}

// EnterTypeDictionary is called when production typeDictionary is entered.
func (s *BaseXsParserListener) EnterTypeDictionary(ctx *TypeDictionaryContext) {}

// ExitTypeDictionary is called when production typeDictionary is exited.
func (s *BaseXsParserListener) ExitTypeDictionary(ctx *TypeDictionaryContext) {}

// EnterTypePackage is called when production typePackage is entered.
func (s *BaseXsParserListener) EnterTypePackage(ctx *TypePackageContext) {}

// ExitTypePackage is called when production typePackage is exited.
func (s *BaseXsParserListener) ExitTypePackage(ctx *TypePackageContext) {}

// EnterTypeFunction is called when production typeFunction is entered.
func (s *BaseXsParserListener) EnterTypeFunction(ctx *TypeFunctionContext) {}

// ExitTypeFunction is called when production typeFunction is exited.
func (s *BaseXsParserListener) ExitTypeFunction(ctx *TypeFunctionContext) {}

// EnterTypeAny is called when production typeAny is entered.
func (s *BaseXsParserListener) EnterTypeAny(ctx *TypeAnyContext) {}

// ExitTypeAny is called when production typeAny is exited.
func (s *BaseXsParserListener) ExitTypeAny(ctx *TypeAnyContext) {}

// EnterTypeFunctionParameterClause is called when production typeFunctionParameterClause is entered.
func (s *BaseXsParserListener) EnterTypeFunctionParameterClause(ctx *TypeFunctionParameterClauseContext) {
}

// ExitTypeFunctionParameterClause is called when production typeFunctionParameterClause is exited.
func (s *BaseXsParserListener) ExitTypeFunctionParameterClause(ctx *TypeFunctionParameterClauseContext) {
}

// EnterTypeBasic is called when production typeBasic is entered.
func (s *BaseXsParserListener) EnterTypeBasic(ctx *TypeBasicContext) {}

// ExitTypeBasic is called when production typeBasic is exited.
func (s *BaseXsParserListener) ExitTypeBasic(ctx *TypeBasicContext) {}

// EnterNilExpr is called when production nilExpr is entered.
func (s *BaseXsParserListener) EnterNilExpr(ctx *NilExprContext) {}

// ExitNilExpr is called when production nilExpr is exited.
func (s *BaseXsParserListener) ExitNilExpr(ctx *NilExprContext) {}

// EnterBoolExpr is called when production boolExpr is entered.
func (s *BaseXsParserListener) EnterBoolExpr(ctx *BoolExprContext) {}

// ExitBoolExpr is called when production boolExpr is exited.
func (s *BaseXsParserListener) ExitBoolExpr(ctx *BoolExprContext) {}

// EnterJudgeType is called when production judgeType is entered.
func (s *BaseXsParserListener) EnterJudgeType(ctx *JudgeTypeContext) {}

// ExitJudgeType is called when production judgeType is exited.
func (s *BaseXsParserListener) ExitJudgeType(ctx *JudgeTypeContext) {}

// EnterJudge is called when production judge is entered.
func (s *BaseXsParserListener) EnterJudge(ctx *JudgeContext) {}

// ExitJudge is called when production judge is exited.
func (s *BaseXsParserListener) ExitJudge(ctx *JudgeContext) {}

// EnterAssign is called when production assign is entered.
func (s *BaseXsParserListener) EnterAssign(ctx *AssignContext) {}

// ExitAssign is called when production assign is exited.
func (s *BaseXsParserListener) ExitAssign(ctx *AssignContext) {}

// EnterAdd is called when production add is entered.
func (s *BaseXsParserListener) EnterAdd(ctx *AddContext) {}

// ExitAdd is called when production add is exited.
func (s *BaseXsParserListener) ExitAdd(ctx *AddContext) {}

// EnterMul is called when production mul is entered.
func (s *BaseXsParserListener) EnterMul(ctx *MulContext) {}

// ExitMul is called when production mul is exited.
func (s *BaseXsParserListener) ExitMul(ctx *MulContext) {}

// EnterPow is called when production pow is entered.
func (s *BaseXsParserListener) EnterPow(ctx *PowContext) {}

// ExitPow is called when production pow is exited.
func (s *BaseXsParserListener) ExitPow(ctx *PowContext) {}

// EnterCall is called when production call is entered.
func (s *BaseXsParserListener) EnterCall(ctx *CallContext) {}

// ExitCall is called when production call is exited.
func (s *BaseXsParserListener) ExitCall(ctx *CallContext) {}

// EnterWave is called when production wave is entered.
func (s *BaseXsParserListener) EnterWave(ctx *WaveContext) {}

// ExitWave is called when production wave is exited.
func (s *BaseXsParserListener) ExitWave(ctx *WaveContext) {}

// EnterId is called when production id is entered.
func (s *BaseXsParserListener) EnterId(ctx *IdContext) {}

// ExitId is called when production id is exited.
func (s *BaseXsParserListener) ExitId(ctx *IdContext) {}

// EnterIdItem is called when production idItem is entered.
func (s *BaseXsParserListener) EnterIdItem(ctx *IdItemContext) {}

// ExitIdItem is called when production idItem is exited.
func (s *BaseXsParserListener) ExitIdItem(ctx *IdItemContext) {}

// EnterEnd is called when production end is entered.
func (s *BaseXsParserListener) EnterEnd(ctx *EndContext) {}

// ExitEnd is called when production end is exited.
func (s *BaseXsParserListener) ExitEnd(ctx *EndContext) {}

// EnterMore is called when production more is entered.
func (s *BaseXsParserListener) EnterMore(ctx *MoreContext) {}

// ExitMore is called when production more is exited.
func (s *BaseXsParserListener) ExitMore(ctx *MoreContext) {}

// EnterLeft_brace is called when production left_brace is entered.
func (s *BaseXsParserListener) EnterLeft_brace(ctx *Left_braceContext) {}

// ExitLeft_brace is called when production left_brace is exited.
func (s *BaseXsParserListener) ExitLeft_brace(ctx *Left_braceContext) {}

// EnterRight_brace is called when production right_brace is entered.
func (s *BaseXsParserListener) EnterRight_brace(ctx *Right_braceContext) {}

// ExitRight_brace is called when production right_brace is exited.
func (s *BaseXsParserListener) ExitRight_brace(ctx *Right_braceContext) {}

// EnterLeft_paren is called when production left_paren is entered.
func (s *BaseXsParserListener) EnterLeft_paren(ctx *Left_parenContext) {}

// ExitLeft_paren is called when production left_paren is exited.
func (s *BaseXsParserListener) ExitLeft_paren(ctx *Left_parenContext) {}

// EnterRight_paren is called when production right_paren is entered.
func (s *BaseXsParserListener) EnterRight_paren(ctx *Right_parenContext) {}

// ExitRight_paren is called when production right_paren is exited.
func (s *BaseXsParserListener) ExitRight_paren(ctx *Right_parenContext) {}

// EnterLeft_brack is called when production left_brack is entered.
func (s *BaseXsParserListener) EnterLeft_brack(ctx *Left_brackContext) {}

// ExitLeft_brack is called when production left_brack is exited.
func (s *BaseXsParserListener) ExitLeft_brack(ctx *Left_brackContext) {}

// EnterRight_brack is called when production right_brack is entered.
func (s *BaseXsParserListener) EnterRight_brack(ctx *Right_brackContext) {}

// ExitRight_brack is called when production right_brack is exited.
func (s *BaseXsParserListener) ExitRight_brack(ctx *Right_brackContext) {}
