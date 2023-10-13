import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:routing_client_dart/src/models/road_helper.dart';
import 'package:routing_client_dart/src/utilities/utils.dart';
/// [OSRMHelper]
/// 
/// this helper fpr OSRMManager that contain URL , intruction generator
mixin OSRMHelper {
  String generatePath(
    String server,
    String waypoints, {
    Profile profile = Profile.route,
    RoadType roadType = RoadType.car,
    bool steps = true,
    Overview overview = Overview.full,
    Geometries geometries = Geometries.polyline,
    bool isCustom = false,
  }) {
    String url = "$server";
    if (! isCustom) {
      url += "/routed-${roadType.name}";
    }
    url += "/${profile.name}/v1/driving/$waypoints";
    var option = "";
    option += "steps=$steps&";
    option += "overview=${overview.value}&";
    option += "geometries=${geometries.value}";
    return "$url?$option";
  }

  String generateTripPath(
    String server,
    String waypoints, {
    RoadType roadType = RoadType.car,
    bool roundTrip = true,
    SourceGeoPointOption source = SourceGeoPointOption.any,
    DestinationGeoPointOption destination = DestinationGeoPointOption.any,
    bool steps = true,
    Overview overview = Overview.full,
    Geometries geometries = Geometries.polyline,
    isCustom = false,
  }) {
    String baseGeneratedUrl = generatePath(
      server,
      waypoints,
      roadType: roadType,
      steps: steps,
      overview: overview,
      profile: Profile.trip,
      geometries: geometries,
      isCustom: isCustom,
    );

    return "$baseGeneratedUrl&source=${source.name}&destination=${destination.name}&roundtrip=$roundTrip";
  }

  Future<Map<String, dynamic>> loadInstructionHelperJson({
    Languages language = Languages.en,
  }) async {
    final loadedJson = await rootBundle.loadString(
        'packages/routing_client_dart/src/assets/${language.name}.json',
        cache: false);
    return json.decode(loadedJson);
  }

  String buildInstruction(
    RoadStep step,
    Map<String, dynamic> instructionsHelper,
    Map<String, dynamic> option,
  ) {
    var type = step.maneuver.maneuverType;
    final instructionsV5 = instructionsHelper['v5'] as Map<String, dynamic>;
    if (!instructionsV5.containsKey(type)) {
      type = 'turn';
    }

    var instructionObject = (instructionsV5[type]
        as Map<String, dynamic>)['default'] as Map<String, dynamic>;
    final omitSide = type == 'off ramp' &&
        ((step.maneuver.modifier?.indexOf(step.drivingSide) ?? 0) >= 0);
    if (step.maneuver.modifier != null &&
        (instructionsV5[type] as Map<String, dynamic>)
            .containsKey(step.maneuver.modifier!) &&
        !omitSide) {
      instructionObject = (instructionsV5[type]
              as Map<String, dynamic>)[step.maneuver.modifier!]
          as Map<String, dynamic>;
    }
    String? laneInstruction;
    switch (step.maneuver.maneuverType) {
      case 'use lane':
        final lane = laneConfig(step);
        if (lane != null) {
          laneInstruction = (((instructionsV5[type]
                  as Map<String, dynamic>)['constants']
              as Map<String, dynamic>)['lanes'] as Map<String, String>)[lane];
        } else {
          instructionObject = ((instructionsV5[type]
                  as Map<String, dynamic>)[step.maneuver.maneuverType]
              as Map<String, dynamic>)['no_lanes'] as Map<String, dynamic>;
        }
        break;
      case 'rotary':
      case 'roundabout':
        if (step.rotaryName != null &&
            step.maneuver.exit != null &&
            instructionObject.containsKey('name_exit')) {
          instructionObject =
              instructionObject['name_exit'] as Map<String, dynamic>;
        } else if (step.rotaryName != null &&
            instructionObject.containsKey('name')) {
          instructionObject = instructionObject['name'] as Map<String, dynamic>;
        } else if (step.maneuver.exit != null &&
            instructionObject.containsKey('exit')) {
          instructionObject = instructionObject['exit'] as Map<String, dynamic>;
        } else {
          instructionObject =
              instructionObject['default'] as Map<String, dynamic>;
        }
        break;
      default:
        break;
    }

    final name = retrieveName(step);
    var instruction = instructionObject['default'] as String;
    if (step.destinations != null &&
        step.exits != null &&
        instructionObject.containsKey('exit_destination')) {
      instruction = instructionObject['exit_destination'] as String;
    } else if (step.destinations != null &&
        instructionObject.containsKey('destination')) {
      instruction = instructionObject['destination'] as String;
    } else if (step.exits != null && instructionObject.containsKey('exit')) {
      instruction = instructionObject['exit'] as String;
    } else if (name.isNotEmpty && instructionObject.containsKey('name')) {
      instruction = instructionObject['name'] as String;
    } else if (option['waypointname'] != null &&
        instructionObject.containsKey('named')) {
      instruction = instructionObject['named'] as String;
    }
    var firstDestination = "";
    try {
      if (step.destinations != null) {
        var destinationSplits = step.destinations!.split(':');
        var destinationRef = destinationSplits.first.split(',').first;
        if (destinationSplits.length > 1) {
          var destination = destinationSplits[1].split(',').first;
          firstDestination = destination;
          if (destination.isNotEmpty && destinationRef.isNotEmpty) {
            firstDestination = "$destinationRef: $destination";
          } else {
            if (destination.isNotEmpty) {
              firstDestination = "$destinationRef: $destination";
            } else if (destinationRef.isNotEmpty) {
              firstDestination = destinationRef;
            }
          }
        } else {
          firstDestination = destinationRef;
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
    String modifierInstruction = "";
    if (step.maneuver.modifier != null) {
      modifierInstruction =
          (instructionsV5["constants"] as Map<String, dynamic>)["modifier"]
              [step.maneuver.modifier] as String;
    }

    String nthWaypoint = "";
    if (option["legIndex"] != null &&
        option["legIndex"] != -1 &&
        option["legIndex"] != option["legCount"]) {
      String key = (option["legIndex"] + 1).toString();
      nthWaypoint = ordinalize(instructionsV5: instructionsV5, key: key);
    }

    String exitOrdinalise = "";
    if (step.maneuver.exit != null) {
      exitOrdinalise = ordinalize(
          instructionsV5: instructionsV5, key: step.maneuver.exit.toString());
    }

    return tokenize(instruction, {
      "way_name": name,
      "destination": firstDestination,
      "exit": step.exits?.split(",").first ?? "",
      "exit_number": exitOrdinalise,
      "rotary_name": step.rotaryName ?? "",
      "lane_instruction": laneInstruction ?? "",
      "modifier": modifierInstruction,
      "direction": directionFromDegree(step.maneuver.bearingBefore),
      "nth": nthWaypoint,
    });
  }

  String tokenize(String instruction, Map<String, String> tokens) {
    String output = instruction;
    tokens.forEach((key, value) {
      output = output.replaceAll('{$key}', value);
    });
    output = output.replaceAll(RegExp(r' {2}'), ' ');
    return output;
  }

  String ordinalize({
    required Map<String, dynamic> instructionsV5,
    required String key,
  }) {
    return (instructionsV5["constants"]["ordinalize"] as Map).containsKey(key)
        ? instructionsV5["constants"]["ordinalize"][key]
        : "";
  }

  String retrieveName(RoadStep step) {
    final refN = step.ref?.split(';').first;
    var n = step.name;
    if (refN != null && refN == n) {
      n = '';
    }
    if (n.isNotEmpty && refN != null) {
      return '${step.name} ($refN)';
    }
    return n;
  }

  String directionFromDegree(double? degree) {
    if (degree == null) {
      return '';
    }
    if (degree >= 0 && degree <= 20) {
      return 'north';
    } else if (degree > 20 && degree < 70) {
      return 'northeast';
    } else if (degree >= 70 && degree <= 110) {
      return 'east';
    } else if (degree > 110 && degree < 160) {
      return 'southeast';
    } else if (degree >= 160 && degree <= 200) {
      return 'south';
    } else if (degree > 200 && degree < 250) {
      return 'southwest';
    } else if (degree >= 250 && degree <= 290) {
      return 'west';
    } else if (degree > 290 && degree < 340) {
      return 'northwest';
    } else if (degree >= 340 && degree <= 360) {
      return 'north';
    } else {
      return '';
    }
  }

  String? laneConfig(RoadStep step) {
    if (step.intersections.isEmpty || step.intersections.first.lanes == null) {
      return null;
    }
    final config = <String>[];
    bool? validity;
    step.intersections.first.lanes?.forEach((lane) {
      if (validity == null || validity != lane.valid) {
        if (lane.valid) {
          config.add('o');
        } else {
          config.add('x');
        }
        validity = lane.valid;
      }
    });
    return config.join();
  }
}
