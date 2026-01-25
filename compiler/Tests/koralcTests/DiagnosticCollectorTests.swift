import Testing
@testable import KoralCompiler

@Suite("DiagnosticCollector Tests")
struct DiagnosticCollectorTests {
    
    // MARK: - Basic Error Collection Tests
    
    @Test("DiagnosticCollector collects errors")
    func testCollectsErrors() {
        let collector = DiagnosticCollector()
        
        collector.error(
            "Test error message",
            at: SourceSpan(startLine: 1, startColumn: 5, endLine: 1, endColumn: 10),
            fileName: "test.koral"
        )
        
        #expect(collector.hasErrors())
        #expect(collector.errorCountValue == 1)
        #expect(collector.getErrors().count == 1)
        
        let error = collector.getErrors()[0]
        #expect(error.message == "Test error message")
        #expect(error.fileName == "test.koral")
        #expect(error.span.start.line == 1)
        #expect(error.span.start.column == 5)
        #expect(error.isPrimary == true)
    }
    
    @Test("DiagnosticCollector collects multiple errors")
    func testCollectsMultipleErrors() {
        let collector = DiagnosticCollector()
        
        collector.error("Error 1", at: SourceSpan(location: SourceLocation(line: 1, column: 1)), fileName: "test.koral")
        collector.error("Error 2", at: SourceSpan(location: SourceLocation(line: 2, column: 1)), fileName: "test.koral")
        collector.error("Error 3", at: SourceSpan(location: SourceLocation(line: 3, column: 1)), fileName: "test.koral")
        
        #expect(collector.errorCountValue == 3)
        #expect(collector.getErrors().count == 3)
    }
    
    // MARK: - Primary vs Secondary Error Tests
    
    @Test("DiagnosticCollector distinguishes primary and secondary errors")
    func testPrimaryAndSecondaryErrors() {
        let collector = DiagnosticCollector()
        
        // Primary error
        collector.error(
            "Primary error",
            at: SourceSpan(location: SourceLocation(line: 1, column: 1)),
            fileName: "test.koral",
            isPrimary: true
        )
        
        // Secondary error
        collector.secondaryError(
            "Secondary error",
            at: SourceSpan(location: SourceLocation(line: 2, column: 1)),
            fileName: "test.koral",
            causedBy: "Primary error"
        )
        
        #expect(collector.errorCountValue == 2)
        #expect(collector.getPrimaryErrors().count == 1)
        #expect(collector.getSecondaryErrors().count == 1)
        
        let primary = collector.getPrimaryErrors()[0]
        #expect(primary.isPrimary == true)
        #expect(primary.message == "Primary error")
        
        let secondary = collector.getSecondaryErrors()[0]
        #expect(secondary.isPrimary == false)
        #expect(secondary.message == "Secondary error")
        #expect(secondary.notes.count == 1)
        #expect(secondary.notes[0].message.contains("caused by"))
    }
    
    // MARK: - Warning Tests
    
    @Test("DiagnosticCollector collects warnings")
    func testCollectsWarnings() {
        let collector = DiagnosticCollector()
        
        collector.warning(
            "Test warning",
            at: SourceSpan(location: SourceLocation(line: 1, column: 1)),
            fileName: "test.koral"
        )
        
        #expect(collector.hasWarnings())
        #expect(collector.warningCountValue == 1)
        #expect(collector.getWarnings().count == 1)
        #expect(!collector.hasErrors())
    }
    
    @Test("DiagnosticCollector separates errors and warnings")
    func testSeparatesErrorsAndWarnings() {
        let collector = DiagnosticCollector()
        
        collector.error("Error", at: SourceSpan(location: SourceLocation(line: 1, column: 1)), fileName: "test.koral")
        collector.warning("Warning", at: SourceSpan(location: SourceLocation(line: 2, column: 1)), fileName: "test.koral")
        
        #expect(collector.errorCountValue == 1)
        #expect(collector.warningCountValue == 1)
        #expect(collector.getErrors().count == 1)
        #expect(collector.getWarnings().count == 1)
        #expect(collector.getDiagnostics().count == 2)
    }
    
    // MARK: - Fix Hint Tests
    
    @Test("DiagnosticCollector stores fix hints")
    func testStoresFixHints() {
        let collector = DiagnosticCollector()
        
        collector.error(
            "Undefined variable 'x'",
            at: SourceSpan(location: SourceLocation(line: 1, column: 1)),
            fileName: "test.koral",
            fixHint: "Did you mean 'y'?"
        )
        
        let error = collector.getErrors()[0]
        #expect(error.fixHint == "Did you mean 'y'?")
    }
    
    // MARK: - Note Tests
    
    @Test("DiagnosticCollector stores notes")
    func testStoresNotes() {
        let collector = DiagnosticCollector()
        
        let notes = [
            DiagnosticNote(message: "First defined here", location: SourceLocation(line: 5, column: 1)),
            DiagnosticNote(message: "Consider renaming")
        ]
        
        collector.error(
            "Duplicate definition",
            at: SourceSpan(location: SourceLocation(line: 10, column: 1)),
            fileName: "test.koral",
            notes: notes
        )
        
        let error = collector.getErrors()[0]
        #expect(error.notes.count == 2)
        #expect(error.notes[0].message == "First defined here")
        #expect(error.notes[0].location?.line == 5)
        #expect(error.notes[1].message == "Consider renaming")
        #expect(error.notes[1].location == nil)
    }
    
    // MARK: - Clear and Merge Tests
    
    @Test("DiagnosticCollector clear removes all diagnostics")
    func testClear() {
        let collector = DiagnosticCollector()
        
        collector.error("Error", at: SourceSpan(location: SourceLocation(line: 1, column: 1)), fileName: "test.koral")
        collector.warning("Warning", at: SourceSpan(location: SourceLocation(line: 2, column: 1)), fileName: "test.koral")
        
        #expect(collector.hasErrors())
        #expect(collector.hasWarnings())
        
        collector.clear()
        
        #expect(!collector.hasErrors())
        #expect(!collector.hasWarnings())
        #expect(collector.getDiagnostics().isEmpty)
    }
    
    @Test("DiagnosticCollector merge combines diagnostics")
    func testMerge() {
        let collector1 = DiagnosticCollector()
        let collector2 = DiagnosticCollector()
        
        collector1.error("Error 1", at: SourceSpan(location: SourceLocation(line: 1, column: 1)), fileName: "file1.koral")
        collector2.error("Error 2", at: SourceSpan(location: SourceLocation(line: 1, column: 1)), fileName: "file2.koral")
        collector2.warning("Warning", at: SourceSpan(location: SourceLocation(line: 2, column: 1)), fileName: "file2.koral")
        
        collector1.merge(collector2)
        
        #expect(collector1.errorCountValue == 2)
        #expect(collector1.warningCountValue == 1)
        #expect(collector1.getDiagnostics().count == 3)
    }
    
    // MARK: - SemanticError Conversion Tests
    
    @Test("DiagnosticCollector converts SemanticError")
    func testConvertsSemanticError() {
        let collector = DiagnosticCollector()
        
        let semanticError = SemanticError(
            .undefinedVariable("x"),
            fileName: "test.koral",
            span: SourceSpan(location: SourceLocation(line: 5, column: 10))
        )
        
        collector.addSemanticError(semanticError)
        
        #expect(collector.hasErrors())
        let error = collector.getErrors()[0]
        #expect(error.message.contains("Undefined variable"))
        #expect(error.message.contains("x"))
        #expect(error.fileName == "test.koral")
        #expect(error.span.start.line == 5)
    }
    
    // MARK: - Formatting Tests
    
    @Test("Diagnostic description includes location")
    func testDiagnosticDescription() {
        let diagnostic = Diagnostic(
            severity: .error,
            message: "Test error",
            span: SourceSpan(startLine: 10, startColumn: 5, endLine: 10, endColumn: 15),
            fileName: "test.koral"
        )
        
        let desc = diagnostic.description
        #expect(desc.contains("test.koral:10:5"))
        #expect(desc.contains("error"))
        #expect(desc.contains("Test error"))
    }
    
    @Test("Secondary error description shows secondary prefix")
    func testSecondaryErrorDescription() {
        let diagnostic = Diagnostic(
            severity: .error,
            message: "Secondary error",
            span: SourceSpan(location: SourceLocation(line: 1, column: 1)),
            fileName: "test.koral",
            isPrimary: false
        )
        
        let desc = diagnostic.description
        #expect(desc.contains("secondary error"))
    }
    
    @Test("Diagnostic description includes fix hint")
    func testDiagnosticDescriptionWithHint() {
        let diagnostic = Diagnostic(
            severity: .error,
            message: "Test error",
            span: SourceSpan(location: SourceLocation(line: 1, column: 1)),
            fileName: "test.koral",
            fixHint: "Try this instead"
        )
        
        let desc = diagnostic.description
        #expect(desc.contains("hint: Try this instead"))
    }
    
    @Test("DiagnosticCollector description shows summary")
    func testCollectorDescription() {
        let collector = DiagnosticCollector()
        
        collector.error("Error 1", at: SourceSpan(location: SourceLocation(line: 1, column: 1)), fileName: "test.koral")
        collector.error("Error 2", at: SourceSpan(location: SourceLocation(line: 2, column: 1)), fileName: "test.koral")
        collector.warning("Warning", at: SourceSpan(location: SourceLocation(line: 3, column: 1)), fileName: "test.koral")
        
        let desc = collector.description
        #expect(desc.contains("2 errors"))
        #expect(desc.contains("1 warning"))
        #expect(desc.contains("generated"))
    }
    
    // MARK: - Source Snippet Formatting Tests
    
    @Test("Diagnostic formatWithSource includes source snippet")
    func testFormatWithSource() {
        let sourceManager = SourceManager()
        sourceManager.loadFile(name: "test.koral", content: "let x = 10\nlet y = x + z\nlet w = 20")
        
        let diagnostic = Diagnostic(
            severity: .error,
            message: "Undefined variable 'z'",
            span: SourceSpan(startLine: 2, startColumn: 13, endLine: 2, endColumn: 14),
            fileName: "test.koral"
        )
        
        let formatted = diagnostic.formatWithSource(sourceManager: sourceManager)
        #expect(formatted.contains("let y = x + z"))
        #expect(formatted.contains("^"))
    }
    
    // MARK: - Property Tests (Error Collection Completeness)
    
    @Test("Property: All errors are collected without stopping")
    func testAllErrorsCollected() {
        let collector = DiagnosticCollector()
        let errorCount = 10
        
        // Simulate collecting multiple errors (as would happen during compilation)
        for i in 1...errorCount {
            collector.error(
                "Error \(i)",
                at: SourceSpan(location: SourceLocation(line: i, column: 1)),
                fileName: "test.koral"
            )
        }
        
        // Verify all errors were collected
        #expect(collector.errorCountValue == errorCount)
        #expect(collector.getErrors().count == errorCount)
        
        // Verify each error is present
        for i in 1...errorCount {
            let hasError = collector.getErrors().contains { $0.message == "Error \(i)" }
            #expect(hasError)
        }
    }
    
    @Test("Property: Error messages include complete location information")
    func testErrorMessagesHaveLocation() {
        let collector = DiagnosticCollector()
        
        // Add errors with various location information
        collector.error("Error with full span", at: SourceSpan(startLine: 5, startColumn: 10, endLine: 5, endColumn: 20), fileName: "test.koral")
        collector.error("Error with point span", at: SourceSpan(location: SourceLocation(line: 10, column: 5)), fileName: "test.koral")
        
        for error in collector.getErrors() {
            // Every error should have a known span
            #expect(error.span.isKnown)
            // Every error should have a file name
            #expect(!error.fileName.isEmpty)
            // Description should include location
            #expect(error.description.contains(error.fileName))
            #expect(error.description.contains("\(error.span.start.line)"))
        }
    }
}
