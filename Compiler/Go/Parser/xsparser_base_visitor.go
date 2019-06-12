// Code generated from XsParser.g4 by ANTLR 4.7.2. DO NOT EDIT.

package parser // XsParser

import "github.com/antlr/antlr4/runtime/Go/antlr"

type BaseXsParserVisitor struct {
	*antlr.BaseParseTreeVisitor
}

func (v *BaseXsParserVisitor) VisitProgram(ctx *ProgramContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitStatement(ctx *StatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitExportStatement(ctx *ExportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitImportStatement(ctx *ImportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNamespaceSupportStatement(ctx *NamespaceSupportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitEnumStatement(ctx *EnumStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitEnumSupportStatement(ctx *EnumSupportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNamespaceVariableStatement(ctx *NamespaceVariableStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNamespaceControlStatement(ctx *NamespaceControlStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNamespaceConstantStatement(ctx *NamespaceConstantStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNamespaceFunctionStatement(ctx *NamespaceFunctionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageStatement(ctx *PackageStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageNewStatement(ctx *PackageNewStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitParameterClausePackage(ctx *ParameterClausePackageContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageSupportStatement(ctx *PackageSupportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageFunctionStatement(ctx *PackageFunctionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageOverrideFunctionStatement(ctx *PackageOverrideFunctionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageVariableStatement(ctx *PackageVariableStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageControlStatement(ctx *PackageControlStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageControlSubStatement(ctx *PackageControlSubStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageOverrideStatement(ctx *PackageOverrideStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPackageExtensionStatement(ctx *PackageExtensionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolStatement(ctx *ProtocolStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolSupportStatement(ctx *ProtocolSupportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolControlStatement(ctx *ProtocolControlStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolControlSubStatement(ctx *ProtocolControlSubStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolFunctionStatement(ctx *ProtocolFunctionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolImplementSupportStatement(ctx *ProtocolImplementSupportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitProtocolImplementStatement(ctx *ProtocolImplementStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitImplementControlStatement(ctx *ImplementControlStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitImplementFunctionStatement(ctx *ImplementFunctionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitImplementEventStatement(ctx *ImplementEventStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitFunctionStatement(ctx *FunctionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitReturnStatement(ctx *ReturnStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitParameterClauseIn(ctx *ParameterClauseInContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitParameterClauseOut(ctx *ParameterClauseOutContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitParameter(ctx *ParameterContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitFunctionSupportStatement(ctx *FunctionSupportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudgeCaseStatement(ctx *JudgeCaseStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCaseDefaultStatement(ctx *CaseDefaultStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCaseExprStatement(ctx *CaseExprStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCaseStatement(ctx *CaseStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudgeStatement(ctx *JudgeStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudgeElseStatement(ctx *JudgeElseStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudgeIfStatement(ctx *JudgeIfStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudgeElseIfStatement(ctx *JudgeElseIfStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLoopStatement(ctx *LoopStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLoopEachStatement(ctx *LoopEachStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLoopCaseStatement(ctx *LoopCaseStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLoopInfiniteStatement(ctx *LoopInfiniteStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLoopJumpStatement(ctx *LoopJumpStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLoopContinueStatement(ctx *LoopContinueStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCheckStatement(ctx *CheckStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitUsingStatement(ctx *UsingStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCheckErrorStatement(ctx *CheckErrorStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCheckFinallyStatment(ctx *CheckFinallyStatmentContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitReportStatement(ctx *ReportStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitIteratorStatement(ctx *IteratorStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitVariableStatement(ctx *VariableStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitVariableDeclaredStatement(ctx *VariableDeclaredStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAssignStatement(ctx *AssignStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitExpressionStatement(ctx *ExpressionStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPrimaryExpression(ctx *PrimaryExpressionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitExpression(ctx *ExpressionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallBase(ctx *CallBaseContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallSelf(ctx *CallSelfContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallNameSpace(ctx *CallNameSpaceContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallExpression(ctx *CallExpressionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTuple(ctx *TupleContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitExpressionList(ctx *ExpressionListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAnnotationSupport(ctx *AnnotationSupportContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAnnotation(ctx *AnnotationContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAnnotationList(ctx *AnnotationListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAnnotationItem(ctx *AnnotationItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAnnotationAssign(ctx *AnnotationAssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallFunc(ctx *CallFuncContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallElement(ctx *CallElementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallPkg(ctx *CallPkgContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallNew(ctx *CallNewContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitGetType(ctx *GetTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeConversion(ctx *TypeConversionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPkgAssign(ctx *PkgAssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPkgAssignElement(ctx *PkgAssignElementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitListAssign(ctx *ListAssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitSetAssign(ctx *SetAssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitDictionaryAssign(ctx *DictionaryAssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCallAwait(ctx *CallAwaitContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitList(ctx *ListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitSet(ctx *SetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitDictionary(ctx *DictionaryContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitDictionaryElement(ctx *DictionaryElementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitSlice(ctx *SliceContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitSliceFull(ctx *SliceFullContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitSliceStart(ctx *SliceStartContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitSliceEnd(ctx *SliceEndContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNameSpace(ctx *NameSpaceContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNameSpaceItem(ctx *NameSpaceItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitName(ctx *NameContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTemplateDefine(ctx *TemplateDefineContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTemplateDefineItem(ctx *TemplateDefineItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTemplateCall(ctx *TemplateCallContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLambda(ctx *LambdaContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLambdaIn(ctx *LambdaInContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPkgAnonymous(ctx *PkgAnonymousContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPkgAnonymousAssign(ctx *PkgAnonymousAssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPkgAnonymousAssignElement(ctx *PkgAnonymousAssignElementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitFunctionExpression(ctx *FunctionExpressionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAnonymousParameterClauseIn(ctx *AnonymousParameterClauseInContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTupleExpression(ctx *TupleExpressionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPlusMinus(ctx *PlusMinusContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNegate(ctx *NegateContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLinq(ctx *LinqContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLinqItem(ctx *LinqItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLinqKeyword(ctx *LinqKeywordContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLinqHeadKeyword(ctx *LinqHeadKeywordContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLinqBodyKeyword(ctx *LinqBodyKeywordContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitStringExpression(ctx *StringExpressionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitStringExpressionElement(ctx *StringExpressionElementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitDataStatement(ctx *DataStatementContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitFloatExpr(ctx *FloatExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitIntegerExpr(ctx *IntegerExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeNotNull(ctx *TypeNotNullContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeReference(ctx *TypeReferenceContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeNullable(ctx *TypeNullableContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeType(ctx *TypeTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeTuple(ctx *TypeTupleContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeArray(ctx *TypeArrayContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeList(ctx *TypeListContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeSet(ctx *TypeSetContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeDictionary(ctx *TypeDictionaryContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypePackage(ctx *TypePackageContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeFunction(ctx *TypeFunctionContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeAny(ctx *TypeAnyContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeFunctionParameterClause(ctx *TypeFunctionParameterClauseContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitTypeBasic(ctx *TypeBasicContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitNilExpr(ctx *NilExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitBoolExpr(ctx *BoolExprContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudgeType(ctx *JudgeTypeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitJudge(ctx *JudgeContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAssign(ctx *AssignContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitAdd(ctx *AddContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitMul(ctx *MulContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitPow(ctx *PowContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitCall(ctx *CallContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitWave(ctx *WaveContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitId(ctx *IdContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitIdItem(ctx *IdItemContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitEnd(ctx *EndContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitMore(ctx *MoreContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLeft_brace(ctx *Left_braceContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitRight_brace(ctx *Right_braceContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLeft_paren(ctx *Left_parenContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitRight_paren(ctx *Right_parenContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitLeft_brack(ctx *Left_brackContext) interface{} {
	return v.VisitChildren(ctx)
}

func (v *BaseXsParserVisitor) VisitRight_brack(ctx *Right_brackContext) interface{} {
	return v.VisitChildren(ctx)
}
