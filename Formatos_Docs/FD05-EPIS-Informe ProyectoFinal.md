![C:\\Users\\EPIS\\Documents\\upt.png](fd05image/media/image1.png){width="1.0926727909011373in"
height="1.468837489063867in"}

**UNIVERSIDAD PRIVADA DE TACNA**

**FACULTAD DE INGENIERIA**

**Escuela Profesional de Ingeniería de Sistemas**

**Informe Final**

**"Proyecto *Evolearn"***

**Curso:**

*Patrones de Software*

**Docente:**

*Mag. Patrick Cuadros Quiroga\
*

> **Integrantes:**

*Akhtar Oviedo, Ahmed Hasan - (2022074261)*

*Anampa Pancca, David Jordan - (2022074268)*

*Salas Jimenez, Walter Emmanuel - (2022073896)*

**Tacna -- Perú**

*2025*

  ----------- -------- ----------- ----------- ---------- ------------------------
  CONTROL DE                                              
  VERSIONES                                               

  Versión     Hecha    Revisada    Aprobada    Fecha      Motivo
              por      por         por                    

  1.0         AHAO,    PCQ         \-          21/09/25   Versión 1.0
              DJAP,                                       
              WESJ                                        
  ----------- -------- ----------- ----------- ---------- ------------------------

INDICE GENERAL

1.  Antecedentes 1

2.  Planteamiento del Problema 4

    a.  Problema

    b.  Justificación

    c.  Alcance

3.  Objetivos 6

4.  Marco Teórico

5.  Desarrollo de la Solución 9

    a.  Análisis de Factibilidad (técnico, económica, operativa, social,
        legal, ambiental)

    b.  Tecnología de Desarrollo

    c.  Metodología de implementación

> (Documento de VISION, SRS, SAD)

6.  Presupuesto 8

7.  Conclusiones 8

**Proyecto Evolearn**

**1. Antecedentes**

En el contexto actual de la educación superior y la formación continua,
los estudiantes se enfrentan a una sobrecarga de información digital,
predominantemente en formato PDF. La metodología de estudio tradicional,
que implica la lectura lineal, el resumen manual y la memorización sin
validación, resulta ineficiente frente a los volúmenes de información
que se manejan hoy en día. Existen herramientas de almacenamiento
(Google Drive, Dropbox) y herramientas de IA genéricas (ChatGPT), pero
existe una fragmentación: no hay una solución móvil integrada que
combine la gestión de archivos académicos con la capacidad pedagógica de
resumir y evaluar automáticamente mediante quizzes. EvoLearn surge para
llenar este vacío, proponiendo una \"evolución del aprendizaje\"
mediante el uso de Inteligencia Artificial aplicada a documentos
estáticos.

**2. Planteamiento del Problema**

> **2.1 Problema Central**
>
> Los estudiantes enfrentan dificultades significativas para procesar,
> resumir y repasar grandes cantidades de material de estudio de manera
> eficiente. La falta de herramientas que automaticen la síntesis de
> información y la ausencia de mecanismos de autoevaluación inmediata
> (quizzes) provocan que el tiempo de estudio se invierta en tareas
> operativas (leer y copiar) en lugar de en el aprendizaje activo y la
> retención del conocimiento.
>
> **2.2 Justificación**
>
> El proyecto EvoLearn propone una solución integral que transforma
> archivos pasivos en experiencias de aprendizaje activo.

-   **Educativo:** Fomenta el \"Active Recall\" (repaso activo) mediante
    quizzes generados automáticamente, mejorando la retención a largo
    plazo.

-   **Tecnológico:** Democratiza el acceso a la Inteligencia Artificial
    (Gemini API) para el análisis de textos académicos complejos en
    dispositivos móviles.

-   **Social:** Reduce la brecha de rendimiento académico al ofrecer a
    estudiantes con dificultades de síntesis una herramienta que
    estructura su estudio.

-   **Económico:** Optimiza el tiempo del estudiante, permitiéndole
    alcanzar mejores resultados con menos horas de trabajo manual
    repetitivo.

**\
**

> **2.3 Alcance**

-   Autenticación: Registro e inicio de sesión seguros.

-   Gestión Documental: Sistema de directorios para organizar y subir
    archivos PDF exclusivamente .

-   Análisis IA: Generación automática de resúmenes (general/detallado)
    en formato Markdown (.md).

-   Evaluación: Generación de Quizzes interactivos con validación y
    justificación (\"el porqué\") de las respuestas.

-   Quedan fuera del MVP: Soporte para archivos Word/Excel, modo offline
    para la generación de contenido IA

3\. Objetivos

> 3.1 Objetivo General
>
> Desarrollar una aplicación móvil modular que integre gestión
> documental e Inteligencia Artificial para optimizar el ciclo de
> estudio, facilitando la síntesis de información y la autoevaluación
> mediante cuestionarios automáticos.
>
> 3.2 Objetivos Específicos

-   Implementar un sistema de gestión de archivos que soporte
    estructuras de directorios y validación de PDFs.

-   Integrar servicios de IA (Gemini) para procesar texto y generar
    resúmenes estructurados en menos de 1 minuto.

-   Desarrollar un motor de evaluación que transforme resúmenes en
    preguntas de opción múltiple con retroalimentación inmediata.

-   Validar la usabilidad del aplicativo asegurando una satisfacción
    superior al 85% en pruebas piloto.

4\. Marco Teórico

El proyecto se sustenta en:

-   Aprendizaje Activo: Metodología pedagógica donde el estudiante
    interactúa con el contenido (quizzes) en lugar de solo recibirlo
    pasivamente.

-   Inteligencia Artificial Generativa (LLMs): Uso de modelos de
    lenguaje para tareas de Procesamiento de Lenguaje Natural (NLP) como
    resumen y extracción de preguntas clave.

-   Arquitectura Móvil (Android): Patrones de diseño modernos (MVVM)
    para asegurar una experiencia de usuario fluida y reactiva.

**5. Desarrollo de la Solución**

**5.1 Análisis de Factibilidad**

  --------------- ------------------------------------------------------------
  **Tipo**        **Descripción**

  **Técnica**     Factible. El equipo domina el desarrollo Android y el
                  consumo de APIs REST (Gemini).

  **Económica**   Inversión moderada (S/. 4,381.00), centrada en costos
                  operativos y horas-hombre, con alto retorno en valor
                  educativo.

  **Operativa**   Alta aceptación esperada debido a la necesidad crítica de
                  optimizar tiempos de estudio.

  **Legal**       Cumple con protección de datos básica; no almacena
                  información sensible personal.

  **Ambiental**   Reduce el uso de papel al fomentar el estudio 100% digital.

  **Tipo**        **Descripción**
  --------------- ------------------------------------------------------------

**5.2 Tecnología de Desarrollo**

-   **Frontend: Android Nativo (Kotlin) / Flutter.**

-   **Almacenamiento Local: Room Database / SQLite.**

-   **Inteligencia Artificial: Google Gemini API.**

-   **Formatos: PDF (entrada) y Markdown (salida).**

-   **Diseño: Material Design**

> **5.3 Metodología de Implementación**

Se aplicó una metodología ágil (Scrum) con iteraciones para el MVP:

-   Visión y Alcance: Definición de requerimientos (FD02, FD03).

-   Arquitectura: Diseño de componentes y diagramas 4+1 (FD04).

-   Desarrollo Incremental: Sprints enfocados en Auth, Gestión de
    Archivos, IA y Quiz.

**6. Cronograma**

  ----------- ----------------------------------------------- --------------
  **Fase**    **Actividades Principales**                     **Duración**

  Semana 1    Planificación, Diseño UI/UX y Configuración de  2 semana
              Proyecto                                        

  Semana 2    Desarrollo de Módulos: Autenticación y Gestión  3 semana
              de Archivos                                     

  Semana 3    Integración con API de IA (Resúmenes) y Motor   2.5 semana
              de Quizzes                                      

  Semana 4    Pruebas (Testing), Corrección de errores y      3 semana
              Documentación                                   
  ----------- ----------------------------------------------- --------------

**7. Presupuesto**

  ------------------------------------------------------- ---------------
  **Concepto**                                            **Costo (S/.)**

  Costos generales (Documentación, materiales)            60.00

  Costos operativos (API consumo, energía, internet)      92.00

  Costos de personal (Equipo de desarrollo)               4,229.90

  **Total estimado**                                      **4,381.00**
  ------------------------------------------------------- ---------------

**\
**

**8. Conclusiones**

-   EvoLearn logra unificar la gestión de documentos y el aprendizaje
    activo en una sola plataforma móvil, eliminando la necesidad de
    múltiples herramientas dispersas.

-   La integración de IA para generar resúmenes y quizzes ha demostrado
    ser técnicamente viable y pedagógicamente valiosa, reduciendo
    significativamente los tiempos de preparación de los estudiantes.

-   El MVP cumple con los indicadores de calidad establecidos,
    ofreciendo una experiencia de usuario fluida y una tasa de éxito en
    la generación de contenido superior al 95%
