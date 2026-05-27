import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'cut/dark_status_bar.dart';
import 'cut/dark_top_bar.dart';
import 'cut/customer_widgets.dart';

class NeatCustomer extends StatelessWidget {
  @Preview(
    name: 'Neat Dark – Customer',
    group: 'Neat Dark Pages',
    size: Size(375, 1546),
  )
  const NeatCustomer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1546,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: Stack(
            children: [
              const Positioned(left: 0, top: 0, child: DarkStatusBar()),
              const Positioned(left: 0, top: 44, child: DarkTopBar()),
              Positioned(
                left: 16,
                top: 156,
                child: const CustomerMetricCard(
                  value: '819%',
                  label: 'Avg engagement rate per post',
                  change: '4.2%',
                ),
              ),
              Positioned(
                left: 16,
                top: 318,
                child: const CustomerMetricCard(
                  value: '247,901',
                  label: 'Audience reached',
                  change: '4.2%',
                ),
              ),
              const Positioned(left: 16, top: 480, child: CustomerGrowthCard()),
              Positioned(
                left: 16,
                top: 882,
                child: const CustomerSocialStatCard(
                  value: '3.978.129',
                  change: '2.4%',
                  label: 'Youtube Subscribers',
                ),
              ),
              Positioned(
                left: 16,
                top: 995,
                child: const CustomerSocialStatCard(
                  value: '780K',
                  change: '1.8%',
                  label: 'Instagram Followers',
                ),
              ),
              const Positioned(
                left: 16,
                top: 1108,
                child: CustomerMessageCard(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
