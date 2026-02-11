use crate::session::{convert_dir_name_to_path, convert_path_to_dir_name};

#[test]
fn test_convert_dir_name_to_path() {
    // Test basic project path
    assert_eq!(
        convert_dir_name_to_path("-Users-ozan-Projects-ai-image-dashboard"),
        "/Users/ozan/Projects/ai-image-dashboard"
    );

    // Test project with multiple dashes
    assert_eq!(
        convert_dir_name_to_path("-Users-ozan-Projects-backend-service-generator-ai"),
        "/Users/ozan/Projects/backend-service-generator-ai"
    );

    // Test UnityProjects
    assert_eq!(
        convert_dir_name_to_path("-Users-ozan-UnityProjects-my-game"),
        "/Users/ozan/UnityProjects/my-game"
    );

    // Test worktree paths (with double dashes -> hidden folders)
    assert_eq!(
        convert_dir_name_to_path("-Users-ozan-Projects-ai-image-dashboard--rsworktree-analytics"),
        "/Users/ozan/Projects/ai-image-dashboard/.rsworktree/analytics"
    );

    // Test multiple hidden folders
    assert_eq!(
        convert_dir_name_to_path("-Users-ozan-Projects-myproject--hidden--subfolder"),
        "/Users/ozan/Projects/myproject/.hidden/.subfolder"
    );

    // Test just Projects folder
    assert_eq!(
        convert_dir_name_to_path("-Users-ozan-Projects"),
        "/Users/ozan/Projects"
    );

    // Note: These test cases would fail with convert_dir_name_to_path because
    // the encoding is ambiguous. The reverse lookup via convert_path_to_dir_name
    // is used for matching instead.
}

#[test]
fn test_convert_path_to_dir_name() {
    // Basic path
    assert_eq!(
        convert_path_to_dir_name("/Users/ozan/Projects/ai-image-dashboard"),
        "-Users-ozan-Projects-ai-image-dashboard"
    );

    // Path with hidden folder (.rsworktree)
    assert_eq!(
        convert_path_to_dir_name(
            "/Users/ozan/Projects/unity-build-service/.rsworktree/improve-prov-prof-creation"
        ),
        "-Users-ozan-Projects-unity-build-service--rsworktree-improve-prov-prof-creation"
    );

    // Path with .worktrees
    assert_eq!(
        convert_path_to_dir_name("/Users/ozan/Projects/autogoals-v2/.worktrees/docker-containers"),
        "-Users-ozan-Projects-autogoals-v2--worktrees-docker-containers"
    );

    // Subfolder path (no hidden folders)
    assert_eq!(
        convert_path_to_dir_name("/Users/ozan/Projects/autogoals-v2/examples/test"),
        "-Users-ozan-Projects-autogoals-v2-examples-test"
    );
}
