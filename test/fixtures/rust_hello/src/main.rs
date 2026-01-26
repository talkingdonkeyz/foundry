fn main() {
    println!("hello from rust");
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_addition() {
        assert_eq!(2 + 2, 4);
    }

    #[test]
    fn test_greeting() {
        let greeting = "hello from rust";
        assert!(greeting.contains("rust"));
    }
}
