import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VolunteerRatingSummary extends StatelessWidget {
  final String volunteerId;

  const VolunteerRatingSummary({super.key, required this.volunteerId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('volunteers')
          .doc(volunteerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Error loading ratings',
            style: TextStyle(color: Colors.red),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink(); // Hide if data doesn't exist
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final double averageRating = (data?['averageRating'] ?? 0.0).toDouble();
        final int totalRatings = data?['totalRatings'] ?? 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rating Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    averageRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(5, (index) {
                          if (index < averageRating.floor()) {
                            return const Icon(Icons.star, color: Colors.amber, size: 28);
                          } else if (index < averageRating && averageRating - index >= 0.5) {
                            return const Icon(Icons.star_half, color: Colors.amber, size: 28);
                          } else {
                            return const Icon(Icons.star_border, color: Colors.amber, size: 28);
                          }
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$totalRatings ${totalRatings == 1 ? 'Rating' : 'Ratings'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}