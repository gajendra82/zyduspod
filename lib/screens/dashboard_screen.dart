import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_bloc.dart';
import 'package:zyduspod/Bloc/hospital_dashboard_event.dart';
import 'package:zyduspod/DocumentUploadScreen.dart';
import 'package:zyduspod/widgets/hospital_dashboard_pane.dart';
import 'package:zyduspod/services/hospital_dashboard_service.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openUploader(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DocumentUploadScreen()),
    );
  }


  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HospitalDashboardBloc(HospitalDashboardService())
        ..add(const HospitalDashboardLoadRequested()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('POD Dashboard'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2C3E50),
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Upload documents',
              onPressed: () => _openUploader(context),
              icon: const Icon(Icons.cloud_upload),
            ),
          ],
        ),
        body: const HospitalDashboardPane(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openUploader(context),
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload'),
          backgroundColor: const Color(0xFF00A0A8),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

}
