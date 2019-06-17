// Code generated from XsParser.g4 by ANTLR 4.7.2. DO NOT EDIT.

package parser // XsParser

import "github.com/antlr/antlr4/runtime/Go/antlr"

// A complete Visitor for a parse tree produced by XsParser.
type XsParserVisitor interface {
	antlr.ParseTreeVisitor

	// Visit a parse tree produced by XsParser#program.
	VisitProgram(ctx *ProgramContext) interface{}

	// Visit a parse tree produced by XsParser#statement.
	VisitStatement(ctx *StatementContext) interface{}

	// Visit a parse tree produced by XsParser#exportStatement.
	VisitExportStatement(ctx *ExportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#importStatement.
	VisitImportStatement(ctx *ImportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#namespaceSupportStatement.
	VisitNamespaceSupportStatement(ctx *NamespaceSupportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#typeAliasStatement.
	VisitTypeAliasStatement(ctx *TypeAliasStatementContext) interface{}

	// Visit a parse tree produced by XsParser#typeRedefineStatement.
	VisitTypeRedefineStatement(ctx *TypeRedefineStatementContext) interface{}

	// Visit a parse tree produced by XsParser#enumStatement.
	VisitEnumStatement(ctx *EnumStatementContext) interface{}

	// Visit a parse tree produced by XsParser#enumSupportStatement.
	VisitEnumSupportStatement(ctx *EnumSupportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#namespaceVariableStatement.
	VisitNamespaceVariableStatement(ctx *NamespaceVariableStatementContext) interface{}

	// Visit a parse tree produced by XsParser#namespaceControlStatement.
	VisitNamespaceControlStatement(ctx *NamespaceControlStatementContext) interface{}

	// Visit a parse tree produced by XsParser#namespaceConstantStatement.
	VisitNamespaceConstantStatement(ctx *NamespaceConstantStatementContext) interface{}

	// Visit a parse tree produced by XsParser#namespaceFunctionStatement.
	VisitNamespaceFunctionStatement(ctx *NamespaceFunctionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#includeStatement.
	VisitIncludeStatement(ctx *IncludeStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageStatement.
	VisitPackageStatement(ctx *PackageStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageNewStatement.
	VisitPackageNewStatement(ctx *PackageNewStatementContext) interface{}

	// Visit a parse tree produced by XsParser#parameterClausePackage.
	VisitParameterClausePackage(ctx *ParameterClausePackageContext) interface{}

	// Visit a parse tree produced by XsParser#packageSupportStatement.
	VisitPackageSupportStatement(ctx *PackageSupportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageFunctionStatement.
	VisitPackageFunctionStatement(ctx *PackageFunctionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageOverrideFunctionStatement.
	VisitPackageOverrideFunctionStatement(ctx *PackageOverrideFunctionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageVariableStatement.
	VisitPackageVariableStatement(ctx *PackageVariableStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageControlStatement.
	VisitPackageControlStatement(ctx *PackageControlStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageControlSubStatement.
	VisitPackageControlSubStatement(ctx *PackageControlSubStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageOverrideStatement.
	VisitPackageOverrideStatement(ctx *PackageOverrideStatementContext) interface{}

	// Visit a parse tree produced by XsParser#packageExtensionStatement.
	VisitPackageExtensionStatement(ctx *PackageExtensionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolStatement.
	VisitProtocolStatement(ctx *ProtocolStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolSupportStatement.
	VisitProtocolSupportStatement(ctx *ProtocolSupportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolControlStatement.
	VisitProtocolControlStatement(ctx *ProtocolControlStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolControlSubStatement.
	VisitProtocolControlSubStatement(ctx *ProtocolControlSubStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolFunctionStatement.
	VisitProtocolFunctionStatement(ctx *ProtocolFunctionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolImplementSupportStatement.
	VisitProtocolImplementSupportStatement(ctx *ProtocolImplementSupportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#protocolImplementStatement.
	VisitProtocolImplementStatement(ctx *ProtocolImplementStatementContext) interface{}

	// Visit a parse tree produced by XsParser#implementControlStatement.
	VisitImplementControlStatement(ctx *ImplementControlStatementContext) interface{}

	// Visit a parse tree produced by XsParser#implementFunctionStatement.
	VisitImplementFunctionStatement(ctx *ImplementFunctionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#implementEventStatement.
	VisitImplementEventStatement(ctx *ImplementEventStatementContext) interface{}

	// Visit a parse tree produced by XsParser#functionStatement.
	VisitFunctionStatement(ctx *FunctionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#returnStatement.
	VisitReturnStatement(ctx *ReturnStatementContext) interface{}

	// Visit a parse tree produced by XsParser#parameterClauseIn.
	VisitParameterClauseIn(ctx *ParameterClauseInContext) interface{}

	// Visit a parse tree produced by XsParser#parameterClauseOut.
	VisitParameterClauseOut(ctx *ParameterClauseOutContext) interface{}

	// Visit a parse tree produced by XsParser#parameter.
	VisitParameter(ctx *ParameterContext) interface{}

	// Visit a parse tree produced by XsParser#functionSupportStatement.
	VisitFunctionSupportStatement(ctx *FunctionSupportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#judgeCaseStatement.
	VisitJudgeCaseStatement(ctx *JudgeCaseStatementContext) interface{}

	// Visit a parse tree produced by XsParser#caseDefaultStatement.
	VisitCaseDefaultStatement(ctx *CaseDefaultStatementContext) interface{}

	// Visit a parse tree produced by XsParser#caseExprStatement.
	VisitCaseExprStatement(ctx *CaseExprStatementContext) interface{}

	// Visit a parse tree produced by XsParser#caseStatement.
	VisitCaseStatement(ctx *CaseStatementContext) interface{}

	// Visit a parse tree produced by XsParser#judgeStatement.
	VisitJudgeStatement(ctx *JudgeStatementContext) interface{}

	// Visit a parse tree produced by XsParser#judgeElseStatement.
	VisitJudgeElseStatement(ctx *JudgeElseStatementContext) interface{}

	// Visit a parse tree produced by XsParser#judgeIfStatement.
	VisitJudgeIfStatement(ctx *JudgeIfStatementContext) interface{}

	// Visit a parse tree produced by XsParser#judgeElseIfStatement.
	VisitJudgeElseIfStatement(ctx *JudgeElseIfStatementContext) interface{}

	// Visit a parse tree produced by XsParser#loopStatement.
	VisitLoopStatement(ctx *LoopStatementContext) interface{}

	// Visit a parse tree produced by XsParser#loopEachStatement.
	VisitLoopEachStatement(ctx *LoopEachStatementContext) interface{}

	// Visit a parse tree produced by XsParser#loopCaseStatement.
	VisitLoopCaseStatement(ctx *LoopCaseStatementContext) interface{}

	// Visit a parse tree produced by XsParser#loopInfiniteStatement.
	VisitLoopInfiniteStatement(ctx *LoopInfiniteStatementContext) interface{}

	// Visit a parse tree produced by XsParser#loopJumpStatement.
	VisitLoopJumpStatement(ctx *LoopJumpStatementContext) interface{}

	// Visit a parse tree produced by XsParser#loopContinueStatement.
	VisitLoopContinueStatement(ctx *LoopContinueStatementContext) interface{}

	// Visit a parse tree produced by XsParser#checkStatement.
	VisitCheckStatement(ctx *CheckStatementContext) interface{}

	// Visit a parse tree produced by XsParser#usingStatement.
	VisitUsingStatement(ctx *UsingStatementContext) interface{}

	// Visit a parse tree produced by XsParser#checkErrorStatement.
	VisitCheckErrorStatement(ctx *CheckErrorStatementContext) interface{}

	// Visit a parse tree produced by XsParser#checkFinallyStatment.
	VisitCheckFinallyStatment(ctx *CheckFinallyStatmentContext) interface{}

	// Visit a parse tree produced by XsParser#reportStatement.
	VisitReportStatement(ctx *ReportStatementContext) interface{}

	// Visit a parse tree produced by XsParser#iteratorStatement.
	VisitIteratorStatement(ctx *IteratorStatementContext) interface{}

	// Visit a parse tree produced by XsParser#variableStatement.
	VisitVariableStatement(ctx *VariableStatementContext) interface{}

	// Visit a parse tree produced by XsParser#variableDeclaredStatement.
	VisitVariableDeclaredStatement(ctx *VariableDeclaredStatementContext) interface{}

	// Visit a parse tree produced by XsParser#assignStatement.
	VisitAssignStatement(ctx *AssignStatementContext) interface{}

	// Visit a parse tree produced by XsParser#expressionStatement.
	VisitExpressionStatement(ctx *ExpressionStatementContext) interface{}

	// Visit a parse tree produced by XsParser#primaryExpression.
	VisitPrimaryExpression(ctx *PrimaryExpressionContext) interface{}

	// Visit a parse tree produced by XsParser#expression.
	VisitExpression(ctx *ExpressionContext) interface{}

	// Visit a parse tree produced by XsParser#callBase.
	VisitCallBase(ctx *CallBaseContext) interface{}

	// Visit a parse tree produced by XsParser#callSelf.
	VisitCallSelf(ctx *CallSelfContext) interface{}

	// Visit a parse tree produced by XsParser#callNameSpace.
	VisitCallNameSpace(ctx *CallNameSpaceContext) interface{}

	// Visit a parse tree produced by XsParser#callExpression.
	VisitCallExpression(ctx *CallExpressionContext) interface{}

	// Visit a parse tree produced by XsParser#tuple.
	VisitTuple(ctx *TupleContext) interface{}

	// Visit a parse tree produced by XsParser#expressionList.
	VisitExpressionList(ctx *ExpressionListContext) interface{}

	// Visit a parse tree produced by XsParser#annotationSupport.
	VisitAnnotationSupport(ctx *AnnotationSupportContext) interface{}

	// Visit a parse tree produced by XsParser#annotation.
	VisitAnnotation(ctx *AnnotationContext) interface{}

	// Visit a parse tree produced by XsParser#annotationList.
	VisitAnnotationList(ctx *AnnotationListContext) interface{}

	// Visit a parse tree produced by XsParser#annotationItem.
	VisitAnnotationItem(ctx *AnnotationItemContext) interface{}

	// Visit a parse tree produced by XsParser#annotationAssign.
	VisitAnnotationAssign(ctx *AnnotationAssignContext) interface{}

	// Visit a parse tree produced by XsParser#callFunc.
	VisitCallFunc(ctx *CallFuncContext) interface{}

	// Visit a parse tree produced by XsParser#callElement.
	VisitCallElement(ctx *CallElementContext) interface{}

	// Visit a parse tree produced by XsParser#callPkg.
	VisitCallPkg(ctx *CallPkgContext) interface{}

	// Visit a parse tree produced by XsParser#callNew.
	VisitCallNew(ctx *CallNewContext) interface{}

	// Visit a parse tree produced by XsParser#getType.
	VisitGetType(ctx *GetTypeContext) interface{}

	// Visit a parse tree produced by XsParser#typeConversion.
	VisitTypeConversion(ctx *TypeConversionContext) interface{}

	// Visit a parse tree produced by XsParser#pkgAssign.
	VisitPkgAssign(ctx *PkgAssignContext) interface{}

	// Visit a parse tree produced by XsParser#pkgAssignElement.
	VisitPkgAssignElement(ctx *PkgAssignElementContext) interface{}

	// Visit a parse tree produced by XsParser#listAssign.
	VisitListAssign(ctx *ListAssignContext) interface{}

	// Visit a parse tree produced by XsParser#setAssign.
	VisitSetAssign(ctx *SetAssignContext) interface{}

	// Visit a parse tree produced by XsParser#dictionaryAssign.
	VisitDictionaryAssign(ctx *DictionaryAssignContext) interface{}

	// Visit a parse tree produced by XsParser#callAwait.
	VisitCallAwait(ctx *CallAwaitContext) interface{}

	// Visit a parse tree produced by XsParser#list.
	VisitList(ctx *ListContext) interface{}

	// Visit a parse tree produced by XsParser#set.
	VisitSet(ctx *SetContext) interface{}

	// Visit a parse tree produced by XsParser#dictionary.
	VisitDictionary(ctx *DictionaryContext) interface{}

	// Visit a parse tree produced by XsParser#dictionaryElement.
	VisitDictionaryElement(ctx *DictionaryElementContext) interface{}

	// Visit a parse tree produced by XsParser#slice.
	VisitSlice(ctx *SliceContext) interface{}

	// Visit a parse tree produced by XsParser#sliceFull.
	VisitSliceFull(ctx *SliceFullContext) interface{}

	// Visit a parse tree produced by XsParser#sliceStart.
	VisitSliceStart(ctx *SliceStartContext) interface{}

	// Visit a parse tree produced by XsParser#sliceEnd.
	VisitSliceEnd(ctx *SliceEndContext) interface{}

	// Visit a parse tree produced by XsParser#nameSpaceItem.
	VisitNameSpaceItem(ctx *NameSpaceItemContext) interface{}

	// Visit a parse tree produced by XsParser#name.
	VisitName(ctx *NameContext) interface{}

	// Visit a parse tree produced by XsParser#templateDefine.
	VisitTemplateDefine(ctx *TemplateDefineContext) interface{}

	// Visit a parse tree produced by XsParser#templateDefineItem.
	VisitTemplateDefineItem(ctx *TemplateDefineItemContext) interface{}

	// Visit a parse tree produced by XsParser#templateCall.
	VisitTemplateCall(ctx *TemplateCallContext) interface{}

	// Visit a parse tree produced by XsParser#lambda.
	VisitLambda(ctx *LambdaContext) interface{}

	// Visit a parse tree produced by XsParser#lambdaIn.
	VisitLambdaIn(ctx *LambdaInContext) interface{}

	// Visit a parse tree produced by XsParser#pkgAnonymous.
	VisitPkgAnonymous(ctx *PkgAnonymousContext) interface{}

	// Visit a parse tree produced by XsParser#pkgAnonymousAssign.
	VisitPkgAnonymousAssign(ctx *PkgAnonymousAssignContext) interface{}

	// Visit a parse tree produced by XsParser#pkgAnonymousAssignElement.
	VisitPkgAnonymousAssignElement(ctx *PkgAnonymousAssignElementContext) interface{}

	// Visit a parse tree produced by XsParser#functionExpression.
	VisitFunctionExpression(ctx *FunctionExpressionContext) interface{}

	// Visit a parse tree produced by XsParser#anonymousParameterClauseIn.
	VisitAnonymousParameterClauseIn(ctx *AnonymousParameterClauseInContext) interface{}

	// Visit a parse tree produced by XsParser#tupleExpression.
	VisitTupleExpression(ctx *TupleExpressionContext) interface{}

	// Visit a parse tree produced by XsParser#plusMinus.
	VisitPlusMinus(ctx *PlusMinusContext) interface{}

	// Visit a parse tree produced by XsParser#negate.
	VisitNegate(ctx *NegateContext) interface{}

	// Visit a parse tree produced by XsParser#linq.
	VisitLinq(ctx *LinqContext) interface{}

	// Visit a parse tree produced by XsParser#linqItem.
	VisitLinqItem(ctx *LinqItemContext) interface{}

	// Visit a parse tree produced by XsParser#linqKeyword.
	VisitLinqKeyword(ctx *LinqKeywordContext) interface{}

	// Visit a parse tree produced by XsParser#linqHeadKeyword.
	VisitLinqHeadKeyword(ctx *LinqHeadKeywordContext) interface{}

	// Visit a parse tree produced by XsParser#linqBodyKeyword.
	VisitLinqBodyKeyword(ctx *LinqBodyKeywordContext) interface{}

	// Visit a parse tree produced by XsParser#stringExpression.
	VisitStringExpression(ctx *StringExpressionContext) interface{}

	// Visit a parse tree produced by XsParser#stringExpressionElement.
	VisitStringExpressionElement(ctx *StringExpressionElementContext) interface{}

	// Visit a parse tree produced by XsParser#dataStatement.
	VisitDataStatement(ctx *DataStatementContext) interface{}

	// Visit a parse tree produced by XsParser#floatExpr.
	VisitFloatExpr(ctx *FloatExprContext) interface{}

	// Visit a parse tree produced by XsParser#integerExpr.
	VisitIntegerExpr(ctx *IntegerExprContext) interface{}

	// Visit a parse tree produced by XsParser#typeNotNull.
	VisitTypeNotNull(ctx *TypeNotNullContext) interface{}

	// Visit a parse tree produced by XsParser#typeReference.
	VisitTypeReference(ctx *TypeReferenceContext) interface{}

	// Visit a parse tree produced by XsParser#typeNullable.
	VisitTypeNullable(ctx *TypeNullableContext) interface{}

	// Visit a parse tree produced by XsParser#typeType.
	VisitTypeType(ctx *TypeTypeContext) interface{}

	// Visit a parse tree produced by XsParser#typeTuple.
	VisitTypeTuple(ctx *TypeTupleContext) interface{}

	// Visit a parse tree produced by XsParser#typeArray.
	VisitTypeArray(ctx *TypeArrayContext) interface{}

	// Visit a parse tree produced by XsParser#typeList.
	VisitTypeList(ctx *TypeListContext) interface{}

	// Visit a parse tree produced by XsParser#typeSet.
	VisitTypeSet(ctx *TypeSetContext) interface{}

	// Visit a parse tree produced by XsParser#typeDictionary.
	VisitTypeDictionary(ctx *TypeDictionaryContext) interface{}

	// Visit a parse tree produced by XsParser#typePackage.
	VisitTypePackage(ctx *TypePackageContext) interface{}

	// Visit a parse tree produced by XsParser#typeFunction.
	VisitTypeFunction(ctx *TypeFunctionContext) interface{}

	// Visit a parse tree produced by XsParser#typeAny.
	VisitTypeAny(ctx *TypeAnyContext) interface{}

	// Visit a parse tree produced by XsParser#typeFunctionParameterClause.
	VisitTypeFunctionParameterClause(ctx *TypeFunctionParameterClauseContext) interface{}

	// Visit a parse tree produced by XsParser#typeBasic.
	VisitTypeBasic(ctx *TypeBasicContext) interface{}

	// Visit a parse tree produced by XsParser#nilExpr.
	VisitNilExpr(ctx *NilExprContext) interface{}

	// Visit a parse tree produced by XsParser#boolExpr.
	VisitBoolExpr(ctx *BoolExprContext) interface{}

	// Visit a parse tree produced by XsParser#judgeType.
	VisitJudgeType(ctx *JudgeTypeContext) interface{}

	// Visit a parse tree produced by XsParser#judge.
	VisitJudge(ctx *JudgeContext) interface{}

	// Visit a parse tree produced by XsParser#assign.
	VisitAssign(ctx *AssignContext) interface{}

	// Visit a parse tree produced by XsParser#add.
	VisitAdd(ctx *AddContext) interface{}

	// Visit a parse tree produced by XsParser#mul.
	VisitMul(ctx *MulContext) interface{}

	// Visit a parse tree produced by XsParser#pow.
	VisitPow(ctx *PowContext) interface{}

	// Visit a parse tree produced by XsParser#call.
	VisitCall(ctx *CallContext) interface{}

	// Visit a parse tree produced by XsParser#wave.
	VisitWave(ctx *WaveContext) interface{}

	// Visit a parse tree produced by XsParser#id.
	VisitId(ctx *IdContext) interface{}

	// Visit a parse tree produced by XsParser#idItem.
	VisitIdItem(ctx *IdItemContext) interface{}

	// Visit a parse tree produced by XsParser#end.
	VisitEnd(ctx *EndContext) interface{}

	// Visit a parse tree produced by XsParser#more.
	VisitMore(ctx *MoreContext) interface{}

	// Visit a parse tree produced by XsParser#left_brace.
	VisitLeft_brace(ctx *Left_braceContext) interface{}

	// Visit a parse tree produced by XsParser#right_brace.
	VisitRight_brace(ctx *Right_braceContext) interface{}

	// Visit a parse tree produced by XsParser#left_paren.
	VisitLeft_paren(ctx *Left_parenContext) interface{}

	// Visit a parse tree produced by XsParser#right_paren.
	VisitRight_paren(ctx *Right_parenContext) interface{}

	// Visit a parse tree produced by XsParser#left_brack.
	VisitLeft_brack(ctx *Left_brackContext) interface{}

	// Visit a parse tree produced by XsParser#right_brack.
	VisitRight_brack(ctx *Right_brackContext) interface{}
}
