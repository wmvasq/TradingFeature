import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myenglishtool/pages/add_conversation_page.dart';
import 'package:myenglishtool/pages/conversations_list_page.dart';
import 'package:myenglishtool/pages/progress_page.dart';
import 'package:myenglishtool/pages/ai_practice_screen.dart';
import 'package:myenglishtool/pages/path_to_english.dart';
import 'package:myenglishtool/pages/trading_dashboard_page.dart'; // Nueva

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF000080)),
        drawerTheme: DrawerThemeData(),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF000080),
          foregroundColor: Color.fromARGB(255, 235, 212, 1), // title & icons
        ),
      ),
      home: const MyHomePage(title: 'My English Tool'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(
          widget.title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: Center(
        child: Image.asset('assets/logo.png', width: 200, height: 200),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: null,
        tooltip: 'Speak',
        child: const Icon(
          Icons.record_voice_over_rounded,
          color: Color(0xFF000080),
        ),
      ),
      drawer: Drawer(
        child: Stack(
          children: [
            Opacity(
              opacity: 0.1, // 👈 faint watermark
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.cover, // or BoxFit.contain depending on your image
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                DrawerHeader(
                  decoration: BoxDecoration(color: Color(0xFF000080)),
                  child: Text(
                    'My English Tool - MENU',
                    style: TextStyle(color: Color.fromARGB(255, 235, 212, 1)),
                  ),
                ),
                ListTile(
                  title: Text(
                    'Add',
                    style: TextStyle(color: Color(0xFF000080)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddConversationPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(
                    'Conversations',
                    style: TextStyle(color: Color(0xFF000080)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ConversationListPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(
                    'Progress',
                    style: TextStyle(color: Color(0xFF000080)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProgressPage()),
                    );
                  },
                ),
                ListTile(
                  title: Text(
                    'AI Practice',
                    style: TextStyle(color: Color(0xFF000080)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AIPracticeScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: Text(
                    'PathToEnglish',
                    style: TextStyle(color: Color(0xFF000080)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PathToEnglish()),
                    );
                  },
                ),
                ListTile(
                  title: Text(
                    'Bitcoin Trading',
                    style: TextStyle(color: Color(0xFF000080)),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TradingDashboardPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
