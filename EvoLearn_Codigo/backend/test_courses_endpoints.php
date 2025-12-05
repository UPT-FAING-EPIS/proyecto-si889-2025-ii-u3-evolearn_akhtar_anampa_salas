<?php
// Test de los endpoints de cursos
require_once __DIR__ . '/includes/db.php';
require_once __DIR__ . '/includes/auth.php';

// Simular un usuario autenticado (user_id = 1)
$_SESSION['user_id'] = 1;

echo "PRUEBAS DE ENDPOINTS DE CURSOS\n";
echo "================================\n\n";

// Test 1: save_courses.php
echo "1. TEST: POST /api/save_courses.php\n";
echo "-----------------------------------\n";

try {
    $pdo = getPDO();
    $user_id = 1;
    
    // Datos de ejemplo
    $tema = "Python para Principiantes";
    $courses = [
        [
            'nombre' => 'Introduction to Python',
            'duracion_horas' => 10,
            'url' => 'https://www.python.org'
        ],
        [
            'nombre' => 'Python Basics',
            'duracion_horas' => 8,
            'url' => 'https://docs.python.org'
        ]
    ];
    
    // Preparar statement
    $stmt = $pdo->prepare("
        INSERT INTO user_courses (user_id, tema, nombre_curso, duracion_horas, url, created_at)
        VALUES (:user_id, :tema, :nombre_curso, :duracion_horas, :url, NOW())
        ON DUPLICATE KEY UPDATE
        duracion_horas = VALUES(duracion_horas),
        created_at = NOW()
    ");
    
    foreach ($courses as $course) {
        $stmt->execute([
            ':user_id' => $user_id,
            ':tema' => $tema,
            ':nombre_curso' => $course['nombre'],
            ':duracion_horas' => $course['duracion_horas'],
            ':url' => $course['url']
        ]);
    }
    
    echo "✓ Se insertaron " . count($courses) . " cursos para el tema: '$tema'\n\n";
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n\n";
}

// Test 2: get_user_course_themes.php
echo "2. TEST: GET /api/get_user_course_themes.php\n";
echo "-------------------------------------------\n";

try {
    $pdo = getPDO();
    $user_id = 1;
    
    $stmt = $pdo->prepare("
        SELECT DISTINCT tema FROM user_courses WHERE user_id = ?
        ORDER BY tema ASC
    ");
    $stmt->execute([$user_id]);
    $themes = $stmt->fetchAll(PDO::FETCH_COLUMN);
    
    echo "✓ Temas encontrados para user_id=$user_id: " . count($themes) . "\n";
    foreach ($themes as $theme) {
        echo "  - $theme\n";
    }
    echo "\n";
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n\n";
}

// Test 3: get_courses_by_theme.php
echo "3. TEST: GET /api/get_courses_by_theme.php?tema=Python\n";
echo "------------------------------------------------------\n";

try {
    $pdo = getPDO();
    $user_id = 1;
    $tema = "Python para Principiantes";
    
    $stmt = $pdo->prepare("
        SELECT id, tema, nombre_curso as nombre, duracion_horas, url, created_at
        FROM user_courses
        WHERE user_id = ? AND tema = ?
        ORDER BY created_at DESC
    ");
    $stmt->execute([$user_id, $tema]);
    $courses = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    echo "✓ Cursos encontrados para tema '$tema': " . count($courses) . "\n";
    foreach ($courses as $course) {
        echo "  - {$course['nombre']} ({$course['duracion_horas']}h)\n";
        echo "    URL: {$course['url']}\n";
    }
    echo "\n";
    
} catch (Exception $e) {
    echo "✗ Error: " . $e->getMessage() . "\n\n";
}

echo "================================\n";
echo "✓ Todos los tests completados!\n";
