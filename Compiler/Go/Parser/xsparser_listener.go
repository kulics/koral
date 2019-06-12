// Code generated from XsParser.g4 by ANTLR 4.7.2. DO NOT EDIT.

package parser // XsParser

import "github.com/antlr/antlr4/runtime/Go/antlr"

// XsParserListener is a complete listener for a parse tree produced by XsParser.
type XsParserListener interface {
	antlr.ParseTreeListener

	// EnterProgram is called when entering the program production.
	EnterProgram(c *ProgramContext)

	// EnterStatement is called when entering the statement production.
	EnterStatement(c *StatementContext)

	// EnterExportStatement is called when entering the exportStatement production.
	EnterExportStatement(c *ExportStatementContext)

	// EnterImportStatement is called when entering the importStatement production.
	EnterImportStatement(c *ImportStatementContext)

	// EnterNamespaceSupportStatement is called when entering the namespaceSupportStatement production.
	EnterNamespaceSupportStatement(c *NamespaceSupportStatementContext)

	// EnterEnumStatement is called when entering the enumStatement production.
	EnterEnumStatement(c *EnumStatementContext)

	// EnterEnumSupportStatement is called when entering the enumSupportStatement production.
	EnterEnumSupportStatement(c *EnumSupportStatementContext)

	// EnterNamespaceVariableStatement is called when entering the namespaceVariableStatement production.
	EnterNamespaceVariableStatement(c *NamespaceVariableStatementContext)

	// EnterNamespaceControlStatement is called when entering the namespaceControlStatement production.
	EnterNamespaceControlStatement(c *NamespaceControlStatementContext)

	// EnterNamespaceConstantStatement is called when entering the namespaceConstantStatement production.
	EnterNamespaceConstantStatement(c *NamespaceConstantStatementContext)

	// EnterNamespaceFunctionStatement is called when entering the namespaceFunctionStatement production.
	EnterNamespaceFunctionStatement(c *NamespaceFunctionStatementContext)

	// EnterPackageStatement is called when entering the packageStatement production.
	EnterPackageStatement(c *PackageStatementContext)

	// EnterPackageNewStatement is called when entering the packageNewStatement production.
	EnterPackageNewStatement(c *PackageNewStatementContext)

	// EnterParameterClausePackage is called when entering the parameterClausePackage production.
	EnterParameterClausePackage(c *ParameterClausePackageContext)

	// EnterPackageSupportStatement is called when entering the packageSupportStatement production.
	EnterPackageSupportStatement(c *PackageSupportStatementContext)

	// EnterPackageFunctionStatement is called when entering the packageFunctionStatement production.
	EnterPackageFunctionStatement(c *PackageFunctionStatementContext)

	// EnterPackageOverrideFunctionStatement is called when entering the packageOverrideFunctionStatement production.
	EnterPackageOverrideFunctionStatement(c *PackageOverrideFunctionStatementContext)

	// EnterPackageVariableStatement is called when entering the packageVariableStatement production.
	EnterPackageVariableStatement(c *PackageVariableStatementContext)

	// EnterPackageControlStatement is called when entering the packageControlStatement production.
	EnterPackageControlStatement(c *PackageControlStatementContext)

	// EnterPackageControlSubStatement is called when entering the packageControlSubStatement production.
	EnterPackageControlSubStatement(c *PackageControlSubStatementContext)

	// EnterPackageOverrideStatement is called when entering the packageOverrideStatement production.
	EnterPackageOverrideStatement(c *PackageOverrideStatementContext)

	// EnterPackageExtensionStatement is called when entering the packageExtensionStatement production.
	EnterPackageExtensionStatement(c *PackageExtensionStatementContext)

	// EnterProtocolStatement is called when entering the protocolStatement production.
	EnterProtocolStatement(c *ProtocolStatementContext)

	// EnterProtocolSupportStatement is called when entering the protocolSupportStatement production.
	EnterProtocolSupportStatement(c *ProtocolSupportStatementContext)

	// EnterProtocolControlStatement is called when entering the protocolControlStatement production.
	EnterProtocolControlStatement(c *ProtocolControlStatementContext)

	// EnterProtocolControlSubStatement is called when entering the protocolControlSubStatement production.
	EnterProtocolControlSubStatement(c *ProtocolControlSubStatementContext)

	// EnterProtocolFunctionStatement is called when entering the protocolFunctionStatement production.
	EnterProtocolFunctionStatement(c *ProtocolFunctionStatementContext)

	// EnterProtocolImplementSupportStatement is called when entering the protocolImplementSupportStatement production.
	EnterProtocolImplementSupportStatement(c *ProtocolImplementSupportStatementContext)

	// EnterProtocolImplementStatement is called when entering the protocolImplementStatement production.
	EnterProtocolImplementStatement(c *ProtocolImplementStatementContext)

	// EnterImplementControlStatement is called when entering the implementControlStatement production.
	EnterImplementControlStatement(c *ImplementControlStatementContext)

	// EnterImplementFunctionStatement is called when entering the implementFunctionStatement production.
	EnterImplementFunctionStatement(c *ImplementFunctionStatementContext)

	// EnterImplementEventStatement is called when entering the implementEventStatement production.
	EnterImplementEventStatement(c *ImplementEventStatementContext)

	// EnterFunctionStatement is called when entering the functionStatement production.
	EnterFunctionStatement(c *FunctionStatementContext)

	// EnterReturnStatement is called when entering the returnStatement production.
	EnterReturnStatement(c *ReturnStatementContext)

	// EnterParameterClauseIn is called when entering the parameterClauseIn production.
	EnterParameterClauseIn(c *ParameterClauseInContext)

	// EnterParameterClauseOut is called when entering the parameterClauseOut production.
	EnterParameterClauseOut(c *ParameterClauseOutContext)

	// EnterParameter is called when entering the parameter production.
	EnterParameter(c *ParameterContext)

	// EnterFunctionSupportStatement is called when entering the functionSupportStatement production.
	EnterFunctionSupportStatement(c *FunctionSupportStatementContext)

	// EnterJudgeCaseStatement is called when entering the judgeCaseStatement production.
	EnterJudgeCaseStatement(c *JudgeCaseStatementContext)

	// EnterCaseDefaultStatement is called when entering the caseDefaultStatement production.
	EnterCaseDefaultStatement(c *CaseDefaultStatementContext)

	// EnterCaseExprStatement is called when entering the caseExprStatement production.
	EnterCaseExprStatement(c *CaseExprStatementContext)

	// EnterCaseStatement is called when entering the caseStatement production.
	EnterCaseStatement(c *CaseStatementContext)

	// EnterJudgeStatement is called when entering the judgeStatement production.
	EnterJudgeStatement(c *JudgeStatementContext)

	// EnterJudgeElseStatement is called when entering the judgeElseStatement production.
	EnterJudgeElseStatement(c *JudgeElseStatementContext)

	// EnterJudgeIfStatement is called when entering the judgeIfStatement production.
	EnterJudgeIfStatement(c *JudgeIfStatementContext)

	// EnterJudgeElseIfStatement is called when entering the judgeElseIfStatement production.
	EnterJudgeElseIfStatement(c *JudgeElseIfStatementContext)

	// EnterLoopStatement is called when entering the loopStatement production.
	EnterLoopStatement(c *LoopStatementContext)

	// EnterLoopEachStatement is called when entering the loopEachStatement production.
	EnterLoopEachStatement(c *LoopEachStatementContext)

	// EnterLoopCaseStatement is called when entering the loopCaseStatement production.
	EnterLoopCaseStatement(c *LoopCaseStatementContext)

	// EnterLoopInfiniteStatement is called when entering the loopInfiniteStatement production.
	EnterLoopInfiniteStatement(c *LoopInfiniteStatementContext)

	// EnterLoopJumpStatement is called when entering the loopJumpStatement production.
	EnterLoopJumpStatement(c *LoopJumpStatementContext)

	// EnterLoopContinueStatement is called when entering the loopContinueStatement production.
	EnterLoopContinueStatement(c *LoopContinueStatementContext)

	// EnterCheckStatement is called when entering the checkStatement production.
	EnterCheckStatement(c *CheckStatementContext)

	// EnterUsingStatement is called when entering the usingStatement production.
	EnterUsingStatement(c *UsingStatementContext)

	// EnterCheckErrorStatement is called when entering the checkErrorStatement production.
	EnterCheckErrorStatement(c *CheckErrorStatementContext)

	// EnterCheckFinallyStatment is called when entering the checkFinallyStatment production.
	EnterCheckFinallyStatment(c *CheckFinallyStatmentContext)

	// EnterReportStatement is called when entering the reportStatement production.
	EnterReportStatement(c *ReportStatementContext)

	// EnterIteratorStatement is called when entering the iteratorStatement production.
	EnterIteratorStatement(c *IteratorStatementContext)

	// EnterVariableStatement is called when entering the variableStatement production.
	EnterVariableStatement(c *VariableStatementContext)

	// EnterVariableDeclaredStatement is called when entering the variableDeclaredStatement production.
	EnterVariableDeclaredStatement(c *VariableDeclaredStatementContext)

	// EnterAssignStatement is called when entering the assignStatement production.
	EnterAssignStatement(c *AssignStatementContext)

	// EnterExpressionStatement is called when entering the expressionStatement production.
	EnterExpressionStatement(c *ExpressionStatementContext)

	// EnterPrimaryExpression is called when entering the primaryExpression production.
	EnterPrimaryExpression(c *PrimaryExpressionContext)

	// EnterExpression is called when entering the expression production.
	EnterExpression(c *ExpressionContext)

	// EnterCallBase is called when entering the callBase production.
	EnterCallBase(c *CallBaseContext)

	// EnterCallSelf is called when entering the callSelf production.
	EnterCallSelf(c *CallSelfContext)

	// EnterCallNameSpace is called when entering the callNameSpace production.
	EnterCallNameSpace(c *CallNameSpaceContext)

	// EnterCallExpression is called when entering the callExpression production.
	EnterCallExpression(c *CallExpressionContext)

	// EnterTuple is called when entering the tuple production.
	EnterTuple(c *TupleContext)

	// EnterExpressionList is called when entering the expressionList production.
	EnterExpressionList(c *ExpressionListContext)

	// EnterAnnotationSupport is called when entering the annotationSupport production.
	EnterAnnotationSupport(c *AnnotationSupportContext)

	// EnterAnnotation is called when entering the annotation production.
	EnterAnnotation(c *AnnotationContext)

	// EnterAnnotationList is called when entering the annotationList production.
	EnterAnnotationList(c *AnnotationListContext)

	// EnterAnnotationItem is called when entering the annotationItem production.
	EnterAnnotationItem(c *AnnotationItemContext)

	// EnterAnnotationAssign is called when entering the annotationAssign production.
	EnterAnnotationAssign(c *AnnotationAssignContext)

	// EnterCallFunc is called when entering the callFunc production.
	EnterCallFunc(c *CallFuncContext)

	// EnterCallElement is called when entering the callElement production.
	EnterCallElement(c *CallElementContext)

	// EnterCallPkg is called when entering the callPkg production.
	EnterCallPkg(c *CallPkgContext)

	// EnterCallNew is called when entering the callNew production.
	EnterCallNew(c *CallNewContext)

	// EnterGetType is called when entering the getType production.
	EnterGetType(c *GetTypeContext)

	// EnterTypeConversion is called when entering the typeConversion production.
	EnterTypeConversion(c *TypeConversionContext)

	// EnterPkgAssign is called when entering the pkgAssign production.
	EnterPkgAssign(c *PkgAssignContext)

	// EnterPkgAssignElement is called when entering the pkgAssignElement production.
	EnterPkgAssignElement(c *PkgAssignElementContext)

	// EnterListAssign is called when entering the listAssign production.
	EnterListAssign(c *ListAssignContext)

	// EnterSetAssign is called when entering the setAssign production.
	EnterSetAssign(c *SetAssignContext)

	// EnterDictionaryAssign is called when entering the dictionaryAssign production.
	EnterDictionaryAssign(c *DictionaryAssignContext)

	// EnterCallAwait is called when entering the callAwait production.
	EnterCallAwait(c *CallAwaitContext)

	// EnterList is called when entering the list production.
	EnterList(c *ListContext)

	// EnterSet is called when entering the set production.
	EnterSet(c *SetContext)

	// EnterDictionary is called when entering the dictionary production.
	EnterDictionary(c *DictionaryContext)

	// EnterDictionaryElement is called when entering the dictionaryElement production.
	EnterDictionaryElement(c *DictionaryElementContext)

	// EnterSlice is called when entering the slice production.
	EnterSlice(c *SliceContext)

	// EnterSliceFull is called when entering the sliceFull production.
	EnterSliceFull(c *SliceFullContext)

	// EnterSliceStart is called when entering the sliceStart production.
	EnterSliceStart(c *SliceStartContext)

	// EnterSliceEnd is called when entering the sliceEnd production.
	EnterSliceEnd(c *SliceEndContext)

	// EnterNameSpace is called when entering the nameSpace production.
	EnterNameSpace(c *NameSpaceContext)

	// EnterNameSpaceItem is called when entering the nameSpaceItem production.
	EnterNameSpaceItem(c *NameSpaceItemContext)

	// EnterName is called when entering the name production.
	EnterName(c *NameContext)

	// EnterTemplateDefine is called when entering the templateDefine production.
	EnterTemplateDefine(c *TemplateDefineContext)

	// EnterTemplateDefineItem is called when entering the templateDefineItem production.
	EnterTemplateDefineItem(c *TemplateDefineItemContext)

	// EnterTemplateCall is called when entering the templateCall production.
	EnterTemplateCall(c *TemplateCallContext)

	// EnterLambda is called when entering the lambda production.
	EnterLambda(c *LambdaContext)

	// EnterLambdaIn is called when entering the lambdaIn production.
	EnterLambdaIn(c *LambdaInContext)

	// EnterPkgAnonymous is called when entering the pkgAnonymous production.
	EnterPkgAnonymous(c *PkgAnonymousContext)

	// EnterPkgAnonymousAssign is called when entering the pkgAnonymousAssign production.
	EnterPkgAnonymousAssign(c *PkgAnonymousAssignContext)

	// EnterPkgAnonymousAssignElement is called when entering the pkgAnonymousAssignElement production.
	EnterPkgAnonymousAssignElement(c *PkgAnonymousAssignElementContext)

	// EnterFunctionExpression is called when entering the functionExpression production.
	EnterFunctionExpression(c *FunctionExpressionContext)

	// EnterAnonymousParameterClauseIn is called when entering the anonymousParameterClauseIn production.
	EnterAnonymousParameterClauseIn(c *AnonymousParameterClauseInContext)

	// EnterTupleExpression is called when entering the tupleExpression production.
	EnterTupleExpression(c *TupleExpressionContext)

	// EnterPlusMinus is called when entering the plusMinus production.
	EnterPlusMinus(c *PlusMinusContext)

	// EnterNegate is called when entering the negate production.
	EnterNegate(c *NegateContext)

	// EnterLinq is called when entering the linq production.
	EnterLinq(c *LinqContext)

	// EnterLinqItem is called when entering the linqItem production.
	EnterLinqItem(c *LinqItemContext)

	// EnterLinqKeyword is called when entering the linqKeyword production.
	EnterLinqKeyword(c *LinqKeywordContext)

	// EnterLinqHeadKeyword is called when entering the linqHeadKeyword production.
	EnterLinqHeadKeyword(c *LinqHeadKeywordContext)

	// EnterLinqBodyKeyword is called when entering the linqBodyKeyword production.
	EnterLinqBodyKeyword(c *LinqBodyKeywordContext)

	// EnterStringExpression is called when entering the stringExpression production.
	EnterStringExpression(c *StringExpressionContext)

	// EnterStringExpressionElement is called when entering the stringExpressionElement production.
	EnterStringExpressionElement(c *StringExpressionElementContext)

	// EnterDataStatement is called when entering the dataStatement production.
	EnterDataStatement(c *DataStatementContext)

	// EnterFloatExpr is called when entering the floatExpr production.
	EnterFloatExpr(c *FloatExprContext)

	// EnterIntegerExpr is called when entering the integerExpr production.
	EnterIntegerExpr(c *IntegerExprContext)

	// EnterTypeNotNull is called when entering the typeNotNull production.
	EnterTypeNotNull(c *TypeNotNullContext)

	// EnterTypeReference is called when entering the typeReference production.
	EnterTypeReference(c *TypeReferenceContext)

	// EnterTypeNullable is called when entering the typeNullable production.
	EnterTypeNullable(c *TypeNullableContext)

	// EnterTypeType is called when entering the typeType production.
	EnterTypeType(c *TypeTypeContext)

	// EnterTypeTuple is called when entering the typeTuple production.
	EnterTypeTuple(c *TypeTupleContext)

	// EnterTypeArray is called when entering the typeArray production.
	EnterTypeArray(c *TypeArrayContext)

	// EnterTypeList is called when entering the typeList production.
	EnterTypeList(c *TypeListContext)

	// EnterTypeSet is called when entering the typeSet production.
	EnterTypeSet(c *TypeSetContext)

	// EnterTypeDictionary is called when entering the typeDictionary production.
	EnterTypeDictionary(c *TypeDictionaryContext)

	// EnterTypePackage is called when entering the typePackage production.
	EnterTypePackage(c *TypePackageContext)

	// EnterTypeFunction is called when entering the typeFunction production.
	EnterTypeFunction(c *TypeFunctionContext)

	// EnterTypeAny is called when entering the typeAny production.
	EnterTypeAny(c *TypeAnyContext)

	// EnterTypeFunctionParameterClause is called when entering the typeFunctionParameterClause production.
	EnterTypeFunctionParameterClause(c *TypeFunctionParameterClauseContext)

	// EnterTypeBasic is called when entering the typeBasic production.
	EnterTypeBasic(c *TypeBasicContext)

	// EnterNilExpr is called when entering the nilExpr production.
	EnterNilExpr(c *NilExprContext)

	// EnterBoolExpr is called when entering the boolExpr production.
	EnterBoolExpr(c *BoolExprContext)

	// EnterJudgeType is called when entering the judgeType production.
	EnterJudgeType(c *JudgeTypeContext)

	// EnterJudge is called when entering the judge production.
	EnterJudge(c *JudgeContext)

	// EnterAssign is called when entering the assign production.
	EnterAssign(c *AssignContext)

	// EnterAdd is called when entering the add production.
	EnterAdd(c *AddContext)

	// EnterMul is called when entering the mul production.
	EnterMul(c *MulContext)

	// EnterPow is called when entering the pow production.
	EnterPow(c *PowContext)

	// EnterCall is called when entering the call production.
	EnterCall(c *CallContext)

	// EnterWave is called when entering the wave production.
	EnterWave(c *WaveContext)

	// EnterId is called when entering the id production.
	EnterId(c *IdContext)

	// EnterIdItem is called when entering the idItem production.
	EnterIdItem(c *IdItemContext)

	// EnterEnd is called when entering the end production.
	EnterEnd(c *EndContext)

	// EnterMore is called when entering the more production.
	EnterMore(c *MoreContext)

	// EnterLeft_brace is called when entering the left_brace production.
	EnterLeft_brace(c *Left_braceContext)

	// EnterRight_brace is called when entering the right_brace production.
	EnterRight_brace(c *Right_braceContext)

	// EnterLeft_paren is called when entering the left_paren production.
	EnterLeft_paren(c *Left_parenContext)

	// EnterRight_paren is called when entering the right_paren production.
	EnterRight_paren(c *Right_parenContext)

	// EnterLeft_brack is called when entering the left_brack production.
	EnterLeft_brack(c *Left_brackContext)

	// EnterRight_brack is called when entering the right_brack production.
	EnterRight_brack(c *Right_brackContext)

	// ExitProgram is called when exiting the program production.
	ExitProgram(c *ProgramContext)

	// ExitStatement is called when exiting the statement production.
	ExitStatement(c *StatementContext)

	// ExitExportStatement is called when exiting the exportStatement production.
	ExitExportStatement(c *ExportStatementContext)

	// ExitImportStatement is called when exiting the importStatement production.
	ExitImportStatement(c *ImportStatementContext)

	// ExitNamespaceSupportStatement is called when exiting the namespaceSupportStatement production.
	ExitNamespaceSupportStatement(c *NamespaceSupportStatementContext)

	// ExitEnumStatement is called when exiting the enumStatement production.
	ExitEnumStatement(c *EnumStatementContext)

	// ExitEnumSupportStatement is called when exiting the enumSupportStatement production.
	ExitEnumSupportStatement(c *EnumSupportStatementContext)

	// ExitNamespaceVariableStatement is called when exiting the namespaceVariableStatement production.
	ExitNamespaceVariableStatement(c *NamespaceVariableStatementContext)

	// ExitNamespaceControlStatement is called when exiting the namespaceControlStatement production.
	ExitNamespaceControlStatement(c *NamespaceControlStatementContext)

	// ExitNamespaceConstantStatement is called when exiting the namespaceConstantStatement production.
	ExitNamespaceConstantStatement(c *NamespaceConstantStatementContext)

	// ExitNamespaceFunctionStatement is called when exiting the namespaceFunctionStatement production.
	ExitNamespaceFunctionStatement(c *NamespaceFunctionStatementContext)

	// ExitPackageStatement is called when exiting the packageStatement production.
	ExitPackageStatement(c *PackageStatementContext)

	// ExitPackageNewStatement is called when exiting the packageNewStatement production.
	ExitPackageNewStatement(c *PackageNewStatementContext)

	// ExitParameterClausePackage is called when exiting the parameterClausePackage production.
	ExitParameterClausePackage(c *ParameterClausePackageContext)

	// ExitPackageSupportStatement is called when exiting the packageSupportStatement production.
	ExitPackageSupportStatement(c *PackageSupportStatementContext)

	// ExitPackageFunctionStatement is called when exiting the packageFunctionStatement production.
	ExitPackageFunctionStatement(c *PackageFunctionStatementContext)

	// ExitPackageOverrideFunctionStatement is called when exiting the packageOverrideFunctionStatement production.
	ExitPackageOverrideFunctionStatement(c *PackageOverrideFunctionStatementContext)

	// ExitPackageVariableStatement is called when exiting the packageVariableStatement production.
	ExitPackageVariableStatement(c *PackageVariableStatementContext)

	// ExitPackageControlStatement is called when exiting the packageControlStatement production.
	ExitPackageControlStatement(c *PackageControlStatementContext)

	// ExitPackageControlSubStatement is called when exiting the packageControlSubStatement production.
	ExitPackageControlSubStatement(c *PackageControlSubStatementContext)

	// ExitPackageOverrideStatement is called when exiting the packageOverrideStatement production.
	ExitPackageOverrideStatement(c *PackageOverrideStatementContext)

	// ExitPackageExtensionStatement is called when exiting the packageExtensionStatement production.
	ExitPackageExtensionStatement(c *PackageExtensionStatementContext)

	// ExitProtocolStatement is called when exiting the protocolStatement production.
	ExitProtocolStatement(c *ProtocolStatementContext)

	// ExitProtocolSupportStatement is called when exiting the protocolSupportStatement production.
	ExitProtocolSupportStatement(c *ProtocolSupportStatementContext)

	// ExitProtocolControlStatement is called when exiting the protocolControlStatement production.
	ExitProtocolControlStatement(c *ProtocolControlStatementContext)

	// ExitProtocolControlSubStatement is called when exiting the protocolControlSubStatement production.
	ExitProtocolControlSubStatement(c *ProtocolControlSubStatementContext)

	// ExitProtocolFunctionStatement is called when exiting the protocolFunctionStatement production.
	ExitProtocolFunctionStatement(c *ProtocolFunctionStatementContext)

	// ExitProtocolImplementSupportStatement is called when exiting the protocolImplementSupportStatement production.
	ExitProtocolImplementSupportStatement(c *ProtocolImplementSupportStatementContext)

	// ExitProtocolImplementStatement is called when exiting the protocolImplementStatement production.
	ExitProtocolImplementStatement(c *ProtocolImplementStatementContext)

	// ExitImplementControlStatement is called when exiting the implementControlStatement production.
	ExitImplementControlStatement(c *ImplementControlStatementContext)

	// ExitImplementFunctionStatement is called when exiting the implementFunctionStatement production.
	ExitImplementFunctionStatement(c *ImplementFunctionStatementContext)

	// ExitImplementEventStatement is called when exiting the implementEventStatement production.
	ExitImplementEventStatement(c *ImplementEventStatementContext)

	// ExitFunctionStatement is called when exiting the functionStatement production.
	ExitFunctionStatement(c *FunctionStatementContext)

	// ExitReturnStatement is called when exiting the returnStatement production.
	ExitReturnStatement(c *ReturnStatementContext)

	// ExitParameterClauseIn is called when exiting the parameterClauseIn production.
	ExitParameterClauseIn(c *ParameterClauseInContext)

	// ExitParameterClauseOut is called when exiting the parameterClauseOut production.
	ExitParameterClauseOut(c *ParameterClauseOutContext)

	// ExitParameter is called when exiting the parameter production.
	ExitParameter(c *ParameterContext)

	// ExitFunctionSupportStatement is called when exiting the functionSupportStatement production.
	ExitFunctionSupportStatement(c *FunctionSupportStatementContext)

	// ExitJudgeCaseStatement is called when exiting the judgeCaseStatement production.
	ExitJudgeCaseStatement(c *JudgeCaseStatementContext)

	// ExitCaseDefaultStatement is called when exiting the caseDefaultStatement production.
	ExitCaseDefaultStatement(c *CaseDefaultStatementContext)

	// ExitCaseExprStatement is called when exiting the caseExprStatement production.
	ExitCaseExprStatement(c *CaseExprStatementContext)

	// ExitCaseStatement is called when exiting the caseStatement production.
	ExitCaseStatement(c *CaseStatementContext)

	// ExitJudgeStatement is called when exiting the judgeStatement production.
	ExitJudgeStatement(c *JudgeStatementContext)

	// ExitJudgeElseStatement is called when exiting the judgeElseStatement production.
	ExitJudgeElseStatement(c *JudgeElseStatementContext)

	// ExitJudgeIfStatement is called when exiting the judgeIfStatement production.
	ExitJudgeIfStatement(c *JudgeIfStatementContext)

	// ExitJudgeElseIfStatement is called when exiting the judgeElseIfStatement production.
	ExitJudgeElseIfStatement(c *JudgeElseIfStatementContext)

	// ExitLoopStatement is called when exiting the loopStatement production.
	ExitLoopStatement(c *LoopStatementContext)

	// ExitLoopEachStatement is called when exiting the loopEachStatement production.
	ExitLoopEachStatement(c *LoopEachStatementContext)

	// ExitLoopCaseStatement is called when exiting the loopCaseStatement production.
	ExitLoopCaseStatement(c *LoopCaseStatementContext)

	// ExitLoopInfiniteStatement is called when exiting the loopInfiniteStatement production.
	ExitLoopInfiniteStatement(c *LoopInfiniteStatementContext)

	// ExitLoopJumpStatement is called when exiting the loopJumpStatement production.
	ExitLoopJumpStatement(c *LoopJumpStatementContext)

	// ExitLoopContinueStatement is called when exiting the loopContinueStatement production.
	ExitLoopContinueStatement(c *LoopContinueStatementContext)

	// ExitCheckStatement is called when exiting the checkStatement production.
	ExitCheckStatement(c *CheckStatementContext)

	// ExitUsingStatement is called when exiting the usingStatement production.
	ExitUsingStatement(c *UsingStatementContext)

	// ExitCheckErrorStatement is called when exiting the checkErrorStatement production.
	ExitCheckErrorStatement(c *CheckErrorStatementContext)

	// ExitCheckFinallyStatment is called when exiting the checkFinallyStatment production.
	ExitCheckFinallyStatment(c *CheckFinallyStatmentContext)

	// ExitReportStatement is called when exiting the reportStatement production.
	ExitReportStatement(c *ReportStatementContext)

	// ExitIteratorStatement is called when exiting the iteratorStatement production.
	ExitIteratorStatement(c *IteratorStatementContext)

	// ExitVariableStatement is called when exiting the variableStatement production.
	ExitVariableStatement(c *VariableStatementContext)

	// ExitVariableDeclaredStatement is called when exiting the variableDeclaredStatement production.
	ExitVariableDeclaredStatement(c *VariableDeclaredStatementContext)

	// ExitAssignStatement is called when exiting the assignStatement production.
	ExitAssignStatement(c *AssignStatementContext)

	// ExitExpressionStatement is called when exiting the expressionStatement production.
	ExitExpressionStatement(c *ExpressionStatementContext)

	// ExitPrimaryExpression is called when exiting the primaryExpression production.
	ExitPrimaryExpression(c *PrimaryExpressionContext)

	// ExitExpression is called when exiting the expression production.
	ExitExpression(c *ExpressionContext)

	// ExitCallBase is called when exiting the callBase production.
	ExitCallBase(c *CallBaseContext)

	// ExitCallSelf is called when exiting the callSelf production.
	ExitCallSelf(c *CallSelfContext)

	// ExitCallNameSpace is called when exiting the callNameSpace production.
	ExitCallNameSpace(c *CallNameSpaceContext)

	// ExitCallExpression is called when exiting the callExpression production.
	ExitCallExpression(c *CallExpressionContext)

	// ExitTuple is called when exiting the tuple production.
	ExitTuple(c *TupleContext)

	// ExitExpressionList is called when exiting the expressionList production.
	ExitExpressionList(c *ExpressionListContext)

	// ExitAnnotationSupport is called when exiting the annotationSupport production.
	ExitAnnotationSupport(c *AnnotationSupportContext)

	// ExitAnnotation is called when exiting the annotation production.
	ExitAnnotation(c *AnnotationContext)

	// ExitAnnotationList is called when exiting the annotationList production.
	ExitAnnotationList(c *AnnotationListContext)

	// ExitAnnotationItem is called when exiting the annotationItem production.
	ExitAnnotationItem(c *AnnotationItemContext)

	// ExitAnnotationAssign is called when exiting the annotationAssign production.
	ExitAnnotationAssign(c *AnnotationAssignContext)

	// ExitCallFunc is called when exiting the callFunc production.
	ExitCallFunc(c *CallFuncContext)

	// ExitCallElement is called when exiting the callElement production.
	ExitCallElement(c *CallElementContext)

	// ExitCallPkg is called when exiting the callPkg production.
	ExitCallPkg(c *CallPkgContext)

	// ExitCallNew is called when exiting the callNew production.
	ExitCallNew(c *CallNewContext)

	// ExitGetType is called when exiting the getType production.
	ExitGetType(c *GetTypeContext)

	// ExitTypeConversion is called when exiting the typeConversion production.
	ExitTypeConversion(c *TypeConversionContext)

	// ExitPkgAssign is called when exiting the pkgAssign production.
	ExitPkgAssign(c *PkgAssignContext)

	// ExitPkgAssignElement is called when exiting the pkgAssignElement production.
	ExitPkgAssignElement(c *PkgAssignElementContext)

	// ExitListAssign is called when exiting the listAssign production.
	ExitListAssign(c *ListAssignContext)

	// ExitSetAssign is called when exiting the setAssign production.
	ExitSetAssign(c *SetAssignContext)

	// ExitDictionaryAssign is called when exiting the dictionaryAssign production.
	ExitDictionaryAssign(c *DictionaryAssignContext)

	// ExitCallAwait is called when exiting the callAwait production.
	ExitCallAwait(c *CallAwaitContext)

	// ExitList is called when exiting the list production.
	ExitList(c *ListContext)

	// ExitSet is called when exiting the set production.
	ExitSet(c *SetContext)

	// ExitDictionary is called when exiting the dictionary production.
	ExitDictionary(c *DictionaryContext)

	// ExitDictionaryElement is called when exiting the dictionaryElement production.
	ExitDictionaryElement(c *DictionaryElementContext)

	// ExitSlice is called when exiting the slice production.
	ExitSlice(c *SliceContext)

	// ExitSliceFull is called when exiting the sliceFull production.
	ExitSliceFull(c *SliceFullContext)

	// ExitSliceStart is called when exiting the sliceStart production.
	ExitSliceStart(c *SliceStartContext)

	// ExitSliceEnd is called when exiting the sliceEnd production.
	ExitSliceEnd(c *SliceEndContext)

	// ExitNameSpace is called when exiting the nameSpace production.
	ExitNameSpace(c *NameSpaceContext)

	// ExitNameSpaceItem is called when exiting the nameSpaceItem production.
	ExitNameSpaceItem(c *NameSpaceItemContext)

	// ExitName is called when exiting the name production.
	ExitName(c *NameContext)

	// ExitTemplateDefine is called when exiting the templateDefine production.
	ExitTemplateDefine(c *TemplateDefineContext)

	// ExitTemplateDefineItem is called when exiting the templateDefineItem production.
	ExitTemplateDefineItem(c *TemplateDefineItemContext)

	// ExitTemplateCall is called when exiting the templateCall production.
	ExitTemplateCall(c *TemplateCallContext)

	// ExitLambda is called when exiting the lambda production.
	ExitLambda(c *LambdaContext)

	// ExitLambdaIn is called when exiting the lambdaIn production.
	ExitLambdaIn(c *LambdaInContext)

	// ExitPkgAnonymous is called when exiting the pkgAnonymous production.
	ExitPkgAnonymous(c *PkgAnonymousContext)

	// ExitPkgAnonymousAssign is called when exiting the pkgAnonymousAssign production.
	ExitPkgAnonymousAssign(c *PkgAnonymousAssignContext)

	// ExitPkgAnonymousAssignElement is called when exiting the pkgAnonymousAssignElement production.
	ExitPkgAnonymousAssignElement(c *PkgAnonymousAssignElementContext)

	// ExitFunctionExpression is called when exiting the functionExpression production.
	ExitFunctionExpression(c *FunctionExpressionContext)

	// ExitAnonymousParameterClauseIn is called when exiting the anonymousParameterClauseIn production.
	ExitAnonymousParameterClauseIn(c *AnonymousParameterClauseInContext)

	// ExitTupleExpression is called when exiting the tupleExpression production.
	ExitTupleExpression(c *TupleExpressionContext)

	// ExitPlusMinus is called when exiting the plusMinus production.
	ExitPlusMinus(c *PlusMinusContext)

	// ExitNegate is called when exiting the negate production.
	ExitNegate(c *NegateContext)

	// ExitLinq is called when exiting the linq production.
	ExitLinq(c *LinqContext)

	// ExitLinqItem is called when exiting the linqItem production.
	ExitLinqItem(c *LinqItemContext)

	// ExitLinqKeyword is called when exiting the linqKeyword production.
	ExitLinqKeyword(c *LinqKeywordContext)

	// ExitLinqHeadKeyword is called when exiting the linqHeadKeyword production.
	ExitLinqHeadKeyword(c *LinqHeadKeywordContext)

	// ExitLinqBodyKeyword is called when exiting the linqBodyKeyword production.
	ExitLinqBodyKeyword(c *LinqBodyKeywordContext)

	// ExitStringExpression is called when exiting the stringExpression production.
	ExitStringExpression(c *StringExpressionContext)

	// ExitStringExpressionElement is called when exiting the stringExpressionElement production.
	ExitStringExpressionElement(c *StringExpressionElementContext)

	// ExitDataStatement is called when exiting the dataStatement production.
	ExitDataStatement(c *DataStatementContext)

	// ExitFloatExpr is called when exiting the floatExpr production.
	ExitFloatExpr(c *FloatExprContext)

	// ExitIntegerExpr is called when exiting the integerExpr production.
	ExitIntegerExpr(c *IntegerExprContext)

	// ExitTypeNotNull is called when exiting the typeNotNull production.
	ExitTypeNotNull(c *TypeNotNullContext)

	// ExitTypeReference is called when exiting the typeReference production.
	ExitTypeReference(c *TypeReferenceContext)

	// ExitTypeNullable is called when exiting the typeNullable production.
	ExitTypeNullable(c *TypeNullableContext)

	// ExitTypeType is called when exiting the typeType production.
	ExitTypeType(c *TypeTypeContext)

	// ExitTypeTuple is called when exiting the typeTuple production.
	ExitTypeTuple(c *TypeTupleContext)

	// ExitTypeArray is called when exiting the typeArray production.
	ExitTypeArray(c *TypeArrayContext)

	// ExitTypeList is called when exiting the typeList production.
	ExitTypeList(c *TypeListContext)

	// ExitTypeSet is called when exiting the typeSet production.
	ExitTypeSet(c *TypeSetContext)

	// ExitTypeDictionary is called when exiting the typeDictionary production.
	ExitTypeDictionary(c *TypeDictionaryContext)

	// ExitTypePackage is called when exiting the typePackage production.
	ExitTypePackage(c *TypePackageContext)

	// ExitTypeFunction is called when exiting the typeFunction production.
	ExitTypeFunction(c *TypeFunctionContext)

	// ExitTypeAny is called when exiting the typeAny production.
	ExitTypeAny(c *TypeAnyContext)

	// ExitTypeFunctionParameterClause is called when exiting the typeFunctionParameterClause production.
	ExitTypeFunctionParameterClause(c *TypeFunctionParameterClauseContext)

	// ExitTypeBasic is called when exiting the typeBasic production.
	ExitTypeBasic(c *TypeBasicContext)

	// ExitNilExpr is called when exiting the nilExpr production.
	ExitNilExpr(c *NilExprContext)

	// ExitBoolExpr is called when exiting the boolExpr production.
	ExitBoolExpr(c *BoolExprContext)

	// ExitJudgeType is called when exiting the judgeType production.
	ExitJudgeType(c *JudgeTypeContext)

	// ExitJudge is called when exiting the judge production.
	ExitJudge(c *JudgeContext)

	// ExitAssign is called when exiting the assign production.
	ExitAssign(c *AssignContext)

	// ExitAdd is called when exiting the add production.
	ExitAdd(c *AddContext)

	// ExitMul is called when exiting the mul production.
	ExitMul(c *MulContext)

	// ExitPow is called when exiting the pow production.
	ExitPow(c *PowContext)

	// ExitCall is called when exiting the call production.
	ExitCall(c *CallContext)

	// ExitWave is called when exiting the wave production.
	ExitWave(c *WaveContext)

	// ExitId is called when exiting the id production.
	ExitId(c *IdContext)

	// ExitIdItem is called when exiting the idItem production.
	ExitIdItem(c *IdItemContext)

	// ExitEnd is called when exiting the end production.
	ExitEnd(c *EndContext)

	// ExitMore is called when exiting the more production.
	ExitMore(c *MoreContext)

	// ExitLeft_brace is called when exiting the left_brace production.
	ExitLeft_brace(c *Left_braceContext)

	// ExitRight_brace is called when exiting the right_brace production.
	ExitRight_brace(c *Right_braceContext)

	// ExitLeft_paren is called when exiting the left_paren production.
	ExitLeft_paren(c *Left_parenContext)

	// ExitRight_paren is called when exiting the right_paren production.
	ExitRight_paren(c *Right_parenContext)

	// ExitLeft_brack is called when exiting the left_brack production.
	ExitLeft_brack(c *Left_brackContext)

	// ExitRight_brack is called when exiting the right_brack production.
	ExitRight_brack(c *Right_brackContext)
}
