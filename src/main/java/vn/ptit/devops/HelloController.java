package vn.ptit.devops;

import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    @GetMapping("/")
    public String hello() {
        return "Hello from PTIT DevOps Session 12 - Le Phu Toan";
    }

    @GetMapping("/api/version")
    public Map<String, String> version() {
        return Map.of("app", "devops-session12-bai5", "version", "1.0.0");
    }
}
