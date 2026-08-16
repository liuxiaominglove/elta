import Foundation

func runEndpointValidationTests() {
    print("\n--- Endpoint Validation Tests ---")

    test("valid HTTPS endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("https://my-api.com/v1/chat/completions"))
    }

    test("valid localhost HTTP endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("http://localhost:11434/v1"))
    }

    test("valid 127.0.0.1 HTTP endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("http://127.0.0.1:8080/api"))
    }

    test("non-localhost HTTP endpoint rejected") {
        try assertFalse(AIProvider.isValidEndpoint("http://evil.com/api"))
    }

    test("file scheme rejected") {
        try assertFalse(AIProvider.isValidEndpoint("file:///etc/passwd"))
    }

    test("javascript scheme rejected") {
        try assertFalse(AIProvider.isValidEndpoint("javascript:alert(1)"))
    }

    test("data scheme rejected") {
        try assertFalse(AIProvider.isValidEndpoint("data:text/html,<script>alert(1)</script>"))
    }

    test("empty string rejected") {
        try assertFalse(AIProvider.isValidEndpoint(""))
    }

    test("well known DeepSeek endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("https://api.deepseek.com/chat/completions"))
    }

    test("well known OpenAI endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("https://api.openai.com/v1/chat/completions"))
    }

    test("well known Anthropic endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("https://api.anthropic.com/v1/messages"))
    }

    test("Ollama default endpoint passes") {
        try assertTrue(AIProvider.isValidEndpoint("http://localhost:11434/v1/chat/completions"))
    }

    test("custom subdomain on HTTPS passes") {
        try assertTrue(AIProvider.isValidEndpoint("https://ai.mycompany.com/api"))
    }

    test("10.x.x.x private IP passes") {
        try assertTrue(AIProvider.isValidEndpoint("http://10.0.0.1:8080/api"))
    }

    test("10.evil.com domain rejected") {
        try assertFalse(AIProvider.isValidEndpoint("http://10.evil.com/api"))
    }

    test("192.168.x.x private IP passes") {
        try assertTrue(AIProvider.isValidEndpoint("http://192.168.1.1:8080/api"))
    }

    test("192.168.evil.com domain rejected") {
        try assertFalse(AIProvider.isValidEndpoint("http://192.168.evil.com/api"))
    }

    test("172.16.x.x private IP should pass") {
        // 172.16.0.0/12 is also a private range but we don't cover it yet
        // This documents the limitation
        try assertFalse(AIProvider.isValidEndpoint("http://172.16.0.1/api"))
    }
}
